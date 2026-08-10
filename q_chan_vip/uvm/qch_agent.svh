// ---------------------------------------------------------------------------
// qch_agent
//
// config 의 role 을 보고 필요한 것만 만든다.
//
//   role                 monitor  sequencer                 driver
//   QCH_ROLE_CONTROLLER  O        1개 (controller)          controller driver
//   QCH_ROLE_DEVICE      O        2개 (response, active)    device driver
//   QCH_ROLE_PASSIVE     O        X                         X
//
// monitor 는 세 경우 모두 만든다. 관찰은 항상 필요하다.
// ---------------------------------------------------------------------------
class qch_agent extends uvm_agent;

  `uvm_component_utils(qch_agent)

  qch_config                    cfg;

  qch_monitor                   mon;

  qch_controller_sequencer      ctrl_seqr;
  qch_controller_driver         ctrl_drv;

  qch_device_response_sequencer rsp_seqr;
  qch_device_active_sequencer   act_seqr;

  qch_device_driver             dev_drv;

  function new(string name = "qch_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(qch_config)::get(this, "", "cfg", cfg))
      `uvm_fatal(get_type_name(), "qch_config 'cfg' not set in config_db")

    // 하위 컴포넌트도 cfg 를 볼 수 있게 한다
    uvm_config_db#(qch_config)::set(this, "*", "cfg", cfg);

    mon = qch_monitor::type_id::create("mon", this);

    case (cfg.role)
      QCH_ROLE_CONTROLLER: begin
        ctrl_seqr = qch_controller_sequencer::type_id::create("ctrl_seqr", this);
        ctrl_drv  = qch_controller_driver::type_id::create("ctrl_drv", this);
      end
      QCH_ROLE_DEVICE: begin
        rsp_seqr = qch_device_response_sequencer::type_id::create("rsp_seqr", this);
        act_seqr = qch_device_active_sequencer::type_id::create("act_seqr", this);
        dev_drv  = qch_device_driver::type_id::create("dev_drv", this);
      end
      QCH_ROLE_PASSIVE: begin
        // monitor 만 만든다
      end
    endcase
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.role == QCH_ROLE_CONTROLLER)
      ctrl_drv.seq_item_port.connect(ctrl_seqr.seq_item_export);

    if (cfg.role == QCH_ROLE_DEVICE) begin
      dev_drv.seq_item_port.connect(rsp_seqr.seq_item_export);
      dev_drv.act_seq_item_port.connect(act_seqr.seq_item_export);
    end
  endfunction

  // DEVICE 역할이면 응답 전담 시퀀스를 자동으로 올린다.
  // 이 시퀀스는 무한 루프이므로 objection 을 걸지 않는다. 걸면 테스트가 끝나지 않는다.
  virtual task run_phase(uvm_phase phase);
    qch_responder_seq rsp_seq;
    if (cfg.role == QCH_ROLE_DEVICE && cfg.start_responder_seq) begin
      rsp_seq = qch_responder_seq::type_id::create("rsp_seq");
      rsp_seq.start(rsp_seqr);
    end
  endtask

endclass
