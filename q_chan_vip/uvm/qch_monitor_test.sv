// ---------------------------------------------------------------------------
// qch_monitor_test
//
// qch_monitor 단위 테스트. driver 없이 테스트가 직접 인터페이스 신호를 흔들고,
// monitor 가 IHI0068D Table 2-1 대로 상태를 복원해 발행하는지 확인한다.
// ---------------------------------------------------------------------------
`include "uvm_macros.svh"
import uvm_pkg::*;
import qch_item_pkg::*;
import qch_agent_pkg::*;

class qch_monitor_test extends uvm_test;
  `uvm_component_utils(qch_monitor_test)

  uvm_analysis_imp #(qch_monitor_item, qch_monitor_test) mon_imp;
  qch_monitor_item collected[$];

  qch_monitor      mon;
  virtual qch_if   vif;

  function new(string name = "qch_monitor_test", uvm_component parent = null);
    super.new(name, parent);
    mon_imp = new("mon_imp", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual qch_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "virtual interface 'vif' not set")
    mon = qch_monitor::type_id::create("mon", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mon.ap.connect(mon_imp);
  endfunction

  virtual function void write(qch_monitor_item t);
    collected.push_back(t);
  endfunction

  // 신호를 한 번에 세팅하고 n 사이클 유지한다.
  // negedge 에서 구동하는 이유: monitor 는 posedge 에서 샘플링하므로, posedge 에
  // 값을 바꾸면 그 사이클에 새 값이 보이는지 옛 값이 보이는지 모호해진다.
  // negedge 에 구동하면 이어지는 n 개의 posedge 가 정확히 새 값을 본다.
  task drive_signals(bit qreqn, bit qacceptn, bit qdeny, bit qactive, int n = 1);
    @(negedge vif.clk);
    vif.QREQn    <= qreqn;
    vif.QACCEPTn <= qacceptn;
    vif.QDENY    <= qdeny;
    vif.QACTIVE  <= qactive;
    repeat (n) @(posedge vif.clk);
  endtask

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // 리셋 구간: monitor 는 아무것도 발행하면 안 된다.
    //
    // 여기서 이미 Q_RUN 값을 실어두는 것이 중요하다. monitor 는 리셋 해제 후
    // 첫 샘플을 "초기 상태" 로 잡고 발행하지 않는데, 그 시점에 다른 값이 실려
    // 있으면 초기 상태가 그 값이 되고, 이후 Q_RUN 으로 바뀌는 순간 의도하지 않은
    // 전이가 하나 더 발행되어 아래 기대 목록과 어긋난다.
    drive_signals(1'b1, 1'b1, 1'b0, 1'b0, 5);

    wait (vif.rst_n === 1'b1);

    // Q_RUN 에서 시작 (첫 샘플은 초기 상태로 잡히고 발행되지 않는다)
    drive_signals(1'b1, 1'b1, 1'b0, 1'b0, 3);

    // accept 경로: Q_RUN -> Q_REQUEST -> Q_STOPPED -> Q_EXIT -> Q_RUN
    drive_signals(1'b0, 1'b1, 1'b0, 1'b0, 4);  // Q_REQUEST, 4 사이클 체류
    drive_signals(1'b0, 1'b0, 1'b0, 1'b0, 2);  // Q_STOPPED
    drive_signals(1'b1, 1'b0, 1'b0, 1'b1, 2);  // Q_EXIT, QACTIVE HIGH
    drive_signals(1'b1, 1'b1, 1'b0, 1'b0, 2);  // Q_RUN

    // deny 경로: Q_RUN -> Q_REQUEST -> Q_DENIED -> Q_CONTINUE -> Q_RUN
    drive_signals(1'b0, 1'b1, 1'b0, 1'b0, 1);  // Q_REQUEST
    drive_signals(1'b0, 1'b1, 1'b1, 1'b0, 1);  // Q_DENIED
    drive_signals(1'b1, 1'b1, 1'b1, 1'b0, 1);  // Q_CONTINUE
    drive_signals(1'b1, 1'b1, 1'b0, 1'b0, 2);  // Q_RUN

    // illegal 조합: QACCEPTn LOW + QDENY HIGH
    drive_signals(1'b1, 1'b0, 1'b1, 1'b0, 2);  // QCH_ST_ILLEGAL
    drive_signals(1'b1, 1'b1, 1'b0, 1'b0, 2);  // Q_RUN 복귀

    check_results();

    phase.drop_objection(this);
  endtask

  task check_results();
    qch_state_e exp_states[$];
    exp_states = '{ QCH_ST_REQUEST, QCH_ST_STOPPED, QCH_ST_EXIT, QCH_ST_RUN,
                    QCH_ST_REQUEST, QCH_ST_DENIED, QCH_ST_CONTINUE, QCH_ST_RUN,
                    QCH_ST_ILLEGAL, QCH_ST_RUN };

    if (collected.size() != exp_states.size()) begin
      `uvm_error("MON", $sformatf("expected %0d transitions, got %0d",
                                  exp_states.size(), collected.size()))
      foreach (collected[i])
        `uvm_info("MON", $sformatf("  [%0d] %s -> %s (%0d cycles)", i,
                  collected[i].prev_state.name(), collected[i].state.name(),
                  collected[i].cycles_in_prev), UVM_LOW)
      return;
    end

    foreach (exp_states[i])
      if (collected[i].state != exp_states[i])
        `uvm_error("MON", $sformatf("transition %0d: expected %s, got %s",
                   i, exp_states[i].name(), collected[i].state.name()))

    // prev_state 가 직전 항목의 state 와 이어져야 한다
    for (int i = 1; i < collected.size(); i++)
      if (collected[i].prev_state != collected[i-1].state)
        `uvm_error("MON", $sformatf(
          "transition %0d: prev_state=%s does not match previous state=%s",
          i, collected[i].prev_state.name(), collected[i-1].state.name()))

    // Q_REQUEST 에 4 사이클 머물렀으므로 다음 전이의 cycles_in_prev 가 4 여야 한다
    if (collected[1].cycles_in_prev != 4)
      `uvm_error("MON", $sformatf(
        "cycles_in_prev for Q_REQUEST: expected 4, got %0d",
        collected[1].cycles_in_prev))

    // qactive 는 전이가 관측된 시점의 값이다. Q_EXIT 구간을 QACTIVE HIGH 로
    // 구동했으므로, Q_EXIT 로 "들어가는" 전이(collected[2] = STOPPED -> EXIT)에서
    // 1 이어야 한다. Q_EXIT 에서 "나가는" 전이(collected[3] = EXIT -> RUN)는 이미
    // Q_RUN 값(QACTIVE LOW)이 실린 뒤라 0 이다.
    if (collected[2].qactive !== 1'b1)
      `uvm_error("MON", "qactive should be 1 on the Q_STOPPED -> Q_EXIT transition")
    if (collected[3].qactive !== 1'b0)
      `uvm_error("MON", "qactive should be 0 on the Q_EXIT -> Q_RUN transition")
  endtask

endclass

// ---------------------------------------------------------------------------
// 시뮬레이션 entry point
// ---------------------------------------------------------------------------
module qch_mon_tb_top;

  logic clk   = 1'b0;
  logic rst_n = 1'b0;

  always #5ns clk = ~clk;

  qch_if u_if (.clk(clk), .rst_n(rst_n));

  initial begin
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual qch_if)::set(null, "*", "vif", u_if);
    run_test("qch_monitor_test");
  end

endmodule
