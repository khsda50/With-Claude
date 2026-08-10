// ---------------------------------------------------------------------------
// qch_loopback_test
//
// DUT 없이 VIP 끼리 마주보게 연결한다.
//
//   [qch_agent : CONTROLLER] ---- qch_if ---- [qch_agent : DEVICE]
//                                   |
//                            [qch_agent : PASSIVE]  (관찰)
//
// 세 agent 가 같은 인터페이스를 공유하되, 구동하는 신호가 modport 로 갈려 있어
// 충돌하지 않는다.
// ---------------------------------------------------------------------------
`include "uvm_macros.svh"
import uvm_pkg::*;
import qch_item_pkg::*;
import qch_agent_pkg::*;

// controller 자극: quiescence 요청과 운영 허용을 번갈아 반복한다
class qch_loopback_seq extends uvm_sequence #(qch_controller_item);
  `uvm_object_utils(qch_loopback_seq)

  int unsigned n_rounds = 20;

  function new(string name = "qch_loopback_seq");
    super.new(name);
  endfunction

  virtual task body();
    qch_controller_item req;

    repeat (n_rounds) begin
      req = qch_controller_item::type_id::create("req_q");
      start_item(req);
      if (!req.randomize() with { action == QCH_REQUEST_QUIESCENCE;
                                  pre_delay_cycles inside {[0:5]};
                                  response_timeout_cycles == 200; })
        `uvm_error(get_type_name(), "randomize() failed on quiescence request")
      finish_item(req);

      req = qch_controller_item::type_id::create("req_r");
      start_item(req);
      if (!req.randomize() with { action == QCH_ALLOW_RUN;
                                  pre_delay_cycles inside {[0:5]};
                                  response_timeout_cycles == 200; })
        `uvm_error(get_type_name(), "randomize() failed on allow-run request")
      finish_item(req);
    end
  endtask
endclass

class qch_loopback_test extends uvm_test;
  `uvm_component_utils(qch_loopback_test)

  uvm_analysis_imp #(qch_monitor_item, qch_loopback_test) mon_imp;
  qch_monitor_item collected[$];

  qch_agent      ctrl_agent, dev_agent, mon_agent;
  qch_config     ctrl_cfg,   dev_cfg,   mon_cfg;
  virtual qch_if vif;

  function new(string name = "qch_loopback_test", uvm_component parent = null);
    super.new(name, parent);
    mon_imp = new("mon_imp", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual qch_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "virtual interface 'vif' not set")

    ctrl_cfg                  = qch_config::type_id::create("ctrl_cfg");
    ctrl_cfg.role             = QCH_ROLE_CONTROLLER;
    ctrl_cfg.reset_qreqn_high = 1'b1;
    uvm_config_db#(qch_config)::set(this, "ctrl_agent", "cfg", ctrl_cfg);

    dev_cfg                     = qch_config::type_id::create("dev_cfg");
    dev_cfg.role                = QCH_ROLE_DEVICE;
    dev_cfg.start_responder_seq = 1'b1;
    dev_cfg.exit_delay_cycles   = 2;
    uvm_config_db#(qch_config)::set(this, "dev_agent", "cfg", dev_cfg);

    mon_cfg      = qch_config::type_id::create("mon_cfg");
    mon_cfg.role = QCH_ROLE_PASSIVE;
    uvm_config_db#(qch_config)::set(this, "mon_agent", "cfg", mon_cfg);

    ctrl_agent = qch_agent::type_id::create("ctrl_agent", this);
    dev_agent  = qch_agent::type_id::create("dev_agent",  this);
    mon_agent  = qch_agent::type_id::create("mon_agent",  this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mon_agent.mon.ap.connect(mon_imp);
  endfunction

  virtual function void write(qch_monitor_item t);
    collected.push_back(t);
  endfunction

  virtual task run_phase(uvm_phase phase);
    qch_loopback_seq seq;

    phase.raise_objection(this);

    // IHI0068D 2.1.2: 리셋 중 device 는 QACCEPTn 과 QDENY 를 둘 다 LOW 로 구동해야
    // 한다. 리셋이 풀리기 직전 값을 확인한다.
    wait (vif.rst_n === 1'b1);
    if (vif.QACCEPTn !== 1'b0)
      `uvm_error("LOOP", $sformatf(
        "at reset release QACCEPTn should be 0, got %b", vif.QACCEPTn))
    if (vif.QDENY !== 1'b0)
      `uvm_error("LOOP", $sformatf(
        "at reset release QDENY should be 0, got %b", vif.QDENY))
    if (vif.QREQn !== ctrl_cfg.reset_qreqn_high)
      `uvm_error("LOOP", $sformatf(
        "at reset release QREQn should be %b (cfg.reset_qreqn_high), got %b",
        ctrl_cfg.reset_qreqn_high, vif.QREQn))

    repeat (5) @(posedge vif.clk);

    seq          = qch_loopback_seq::type_id::create("seq");
    seq.n_rounds = 20;
    seq.start(ctrl_agent.ctrl_seqr);

    repeat (50) @(posedge vif.clk);
    check_results();

    phase.drop_objection(this);
  endtask

  task check_results();
    bit seen[qch_state_e];

    if (collected.size() == 0) begin
      `uvm_error("LOOP", "monitor observed no transitions at all")
      return;
    end

    foreach (collected[i]) begin
      seen[collected[i].state] = 1'b1;

      // 상태 전이가 끊기지 않고 이어져야 한다
      if (i > 0 && collected[i].prev_state != collected[i-1].state)
        `uvm_error("LOOP", $sformatf(
          "transition %0d: prev_state=%s does not match previous state=%s",
          i, collected[i].prev_state.name(), collected[i-1].state.name()))
    end

    // illegal 상태는 절대 나오면 안 된다
    if (seen.exists(QCH_ST_ILLEGAL))
      `uvm_error("LOOP", "QCH_ST_ILLEGAL was observed — driver drove an illegal combination")

    // accept 경로와 deny 경로를 모두 밟았어야 한다.
    // responder 시퀀스가 policy 를 50:50 으로 뽑으므로 20 라운드면 양쪽 다 나온다.
    if (!seen.exists(QCH_ST_STOPPED))
      `uvm_error("LOOP", "never reached QCH_ST_STOPPED (accept path untested)")
    if (!seen.exists(QCH_ST_DENIED))
      `uvm_error("LOOP", "never reached QCH_ST_DENIED (deny path untested)")
    if (!seen.exists(QCH_ST_CONTINUE))
      `uvm_error("LOOP", "never reached QCH_ST_CONTINUE")
    if (!seen.exists(QCH_ST_EXIT))
      `uvm_error("LOOP", "never reached QCH_ST_EXIT")
    if (!seen.exists(QCH_ST_REQUEST))
      `uvm_error("LOOP", "never reached QCH_ST_REQUEST")
    if (!seen.exists(QCH_ST_RUN))
      `uvm_error("LOOP", "never reached QCH_ST_RUN")

    `uvm_info("LOOP", $sformatf("observed %0d transitions", collected.size()), UVM_LOW)
  endtask

endclass

// ---------------------------------------------------------------------------
// qch_delay_test
//
// device 의 response_delay_cycles 가 실제 파형에 반영되는지 확인한다.
// responder 자동 기동을 끄고, 지연을 고정한 자체 시퀀스를 올린 뒤 monitor 가
// 관측한 Q_REQUEST 체류 시간을 본다.
//
// 정확한 사이클 수는 샘플링 오프셋 때문에 예측이 어려우므로 범위로 확인한다.
// 지연이 무시되면 체류가 1~2 사이클에 그치므로 아래 범위에서 걸린다.
// ---------------------------------------------------------------------------
class qch_fixed_delay_seq extends uvm_sequence #(qch_device_response_item);
  `uvm_object_utils(qch_fixed_delay_seq)

  int unsigned fixed_delay = 8;

  function new(string name = "qch_fixed_delay_seq");
    super.new(name);
  endfunction

  virtual task body();
    qch_device_response_item req;
    forever begin
      req = qch_device_response_item::type_id::create("fixed_req");
      start_item(req);
      if (!req.randomize() with { policy                == QCH_ACCEPT;
                                  response_delay_cycles == fixed_delay; })
        `uvm_error(get_type_name(), "randomize() failed on fixed delay item")
      finish_item(req);
    end
  endtask
endclass

class qch_delay_test extends uvm_test;
  `uvm_component_utils(qch_delay_test)

  uvm_analysis_imp #(qch_monitor_item, qch_delay_test) mon_imp;
  qch_monitor_item collected[$];

  qch_agent      ctrl_agent, dev_agent, mon_agent;
  qch_config     ctrl_cfg,   dev_cfg,   mon_cfg;
  virtual qch_if vif;

  localparam int unsigned FIXED_DELAY = 8;

  function new(string name = "qch_delay_test", uvm_component parent = null);
    super.new(name, parent);
    mon_imp = new("mon_imp", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual qch_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "virtual interface 'vif' not set")

    ctrl_cfg                  = qch_config::type_id::create("ctrl_cfg");
    ctrl_cfg.role             = QCH_ROLE_CONTROLLER;
    ctrl_cfg.reset_qreqn_high = 1'b1;
    uvm_config_db#(qch_config)::set(this, "ctrl_agent", "cfg", ctrl_cfg);

    dev_cfg                     = qch_config::type_id::create("dev_cfg");
    dev_cfg.role                = QCH_ROLE_DEVICE;
    dev_cfg.start_responder_seq = 1'b0;   // 자체 시퀀스를 올린다
    dev_cfg.exit_delay_cycles   = 0;
    uvm_config_db#(qch_config)::set(this, "dev_agent", "cfg", dev_cfg);

    mon_cfg      = qch_config::type_id::create("mon_cfg");
    mon_cfg.role = QCH_ROLE_PASSIVE;
    uvm_config_db#(qch_config)::set(this, "mon_agent", "cfg", mon_cfg);

    ctrl_agent = qch_agent::type_id::create("ctrl_agent", this);
    dev_agent  = qch_agent::type_id::create("dev_agent",  this);
    mon_agent  = qch_agent::type_id::create("mon_agent",  this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mon_agent.mon.ap.connect(mon_imp);
  endfunction

  virtual function void write(qch_monitor_item t);
    collected.push_back(t);
  endfunction

  virtual task run_phase(uvm_phase phase);
    qch_fixed_delay_seq dly_seq;
    qch_loopback_seq    ctrl_seq;

    phase.raise_objection(this);

    wait (vif.rst_n === 1'b1);
    repeat (5) @(posedge vif.clk);

    dly_seq             = qch_fixed_delay_seq::type_id::create("dly_seq");
    dly_seq.fixed_delay = FIXED_DELAY;
    fork
      dly_seq.start(dev_agent.rsp_seqr);
    join_none

    ctrl_seq          = qch_loopback_seq::type_id::create("ctrl_seq");
    ctrl_seq.n_rounds = 5;
    ctrl_seq.start(ctrl_agent.ctrl_seqr);

    repeat (30) @(posedge vif.clk);
    check_delay();

    phase.drop_objection(this);
  endtask

  task check_delay();
    int n_checked = 0;

    // Q_REQUEST -> Q_STOPPED 전이의 cycles_in_prev 가 Q_REQUEST 체류 시간이다.
    foreach (collected[i]) begin
      if (collected[i].prev_state == QCH_ST_REQUEST &&
          collected[i].state      == QCH_ST_STOPPED) begin
        n_checked++;
        // 정확한 사이클 수는 controller 의 QREQn 구동 엣지와 monitor 의 샘플링
        // 엣지 관계에 따라 1~2 사이클 흔들린다. 양쪽에 여유를 두되, 지연이 아예
        // 무시된 경우(체류 1~2 사이클)는 확실히 걸리도록 폭을 잡는다.
        if (collected[i].cycles_in_prev < FIXED_DELAY - 2 ||
            collected[i].cycles_in_prev > FIXED_DELAY + 3)
          `uvm_error("DLY", $sformatf(
            "Q_REQUEST dwell = %0d cycles, expected within [%0d:%0d] for response_delay_cycles=%0d",
            collected[i].cycles_in_prev, FIXED_DELAY - 2, FIXED_DELAY + 3, FIXED_DELAY))
      end
    end

    if (n_checked == 0)
      `uvm_error("DLY", "no Q_REQUEST -> Q_STOPPED transition was observed")
    else
      `uvm_info("DLY", $sformatf("checked %0d accept transitions", n_checked), UVM_LOW)
  endtask

endclass

// ---------------------------------------------------------------------------
// 시뮬레이션 entry point
// ---------------------------------------------------------------------------
module qch_loopback_tb_top;

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
    run_test("qch_loopback_test");
  end

endmodule
