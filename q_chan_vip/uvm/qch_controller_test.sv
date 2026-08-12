// ---------------------------------------------------------------------------
// qch_controller_test
//
// qch_controller_driver 단위 테스트. device 쪽은 실제 driver 대신 테스트가
// 직접 QACCEPTn/QDENY 를 흔들어 흉내낸다.
// ---------------------------------------------------------------------------
`include "uvm_macros.svh"
import uvm_pkg::*;
import qch_item_pkg::*;
import qch_agent_pkg::*;

// qch_ctrl_smoke_seq 는 qch_seq_lib.svh(패키지)로 옮겼다. 여기서 다시 정의하지 않는다.

class qch_controller_test extends uvm_test;
  `uvm_component_utils(qch_controller_test)

  uvm_analysis_imp #(qch_monitor_item, qch_controller_test) mon_imp;
  qch_monitor_item collected[$];

  qch_agent      agent;
  qch_config     cfg;
  virtual qch_if vif;

  function new(string name = "qch_controller_test", uvm_component parent = null);
    super.new(name, parent);
    mon_imp = new("mon_imp", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual qch_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "virtual interface 'vif' not set")

    cfg                  = qch_config::type_id::create("cfg");
    cfg.role             = QCH_ROLE_CONTROLLER;
    cfg.reset_qreqn_high = 1'b1;
    uvm_config_db#(qch_config)::set(this, "agent", "cfg", cfg);

    agent = qch_agent::type_id::create("agent", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.mon.ap.connect(mon_imp);
  endfunction

  virtual function void write(qch_monitor_item t);
    collected.push_back(t);
  endfunction

  // device 흉내: QREQn 이 내려오면 3 사이클 뒤 QACCEPTn 을 내리고,
  //              QREQn 이 올라오면 2 사이클 뒤 QACCEPTn 을 올린다.
  task fake_device();
    vif.QACCEPTn <= 1'b0;
    vif.QDENY    <= 1'b0;
    vif.QACTIVE  <= 1'b0;
    wait (vif.rst_n === 1'b1);

    // 리셋에서 QREQn HIGH 로 나왔으므로 Q_EXIT -> Q_RUN 으로 진행시킨다
    repeat (2) @(posedge vif.clk);
    vif.QACCEPTn <= 1'b1;

    forever begin
      @(negedge vif.QREQn);
      repeat (3) @(posedge vif.clk);
      vif.QACCEPTn <= 1'b0;

      @(posedge vif.QREQn);
      repeat (2) @(posedge vif.clk);
      vif.QACCEPTn <= 1'b1;
    end
  endtask

  virtual task run_phase(uvm_phase phase);
    qch_ctrl_smoke_seq seq;

    phase.raise_objection(this);

    fork
      fake_device();
    join_none

    wait (vif.rst_n === 1'b1);
    repeat (5) @(posedge vif.clk);

    seq = qch_ctrl_smoke_seq::type_id::create("seq");
    seq.start(agent.ctrl_seqr);

    repeat (20) @(posedge vif.clk);
    check_results(seq);

    phase.drop_objection(this);
  endtask

  task check_results(qch_ctrl_smoke_seq seq);
    qch_controller_item req0, req1;

    if (seq.sent.size() != 2) begin
      `uvm_error("CTRL", $sformatf("expected 2 sent items, got %0d", seq.sent.size()))
      return;
    end
    req0 = seq.sent[0];
    req1 = seq.sent[1];

    // 요청에 대해 accept 를 관측했어야 한다
    if (req0.observed_response != QCH_RSP_ACCEPTED)
      `uvm_error("CTRL", $sformatf(
        "req0 (REQUEST_QUIESCENCE): expected QCH_RSP_ACCEPTED, got %s",
        req0.observed_response.name()))

    // fake_device 가 3 사이클 뒤 응답하므로 latency 가 0 보다 커야 한다
    if (req0.response_latency_cycles == 0)
      `uvm_error("CTRL", "req0 response_latency_cycles should be greater than 0")

    // 운영 허용 요청도 완료되었어야 한다
    if (req1.observed_response != QCH_RSP_ACCEPTED)
      `uvm_error("CTRL", $sformatf(
        "req1 (ALLOW_RUN): expected QCH_RSP_ACCEPTED, got %s",
        req1.observed_response.name()))

    // monitor 가 Q_STOPPED 를 관측했어야 한다
    begin
      bit saw_stopped = 1'b0;
      foreach (collected[i])
        if (collected[i].state == QCH_ST_STOPPED) saw_stopped = 1'b1;
      if (!saw_stopped)
        `uvm_error("CTRL", "monitor never observed QCH_ST_STOPPED")
    end

    // illegal 상태는 나오면 안 된다
    foreach (collected[i])
      if (collected[i].state == QCH_ST_ILLEGAL)
        `uvm_error("CTRL", $sformatf("illegal state observed at transition %0d", i))
  endtask

endclass

// ---------------------------------------------------------------------------
// 시뮬레이션 entry point
// ---------------------------------------------------------------------------
module qch_ctrl_tb_top;

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
    run_test("qch_controller_test");
  end

endmodule
