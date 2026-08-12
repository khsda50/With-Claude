// ---------------------------------------------------------------------------
// qch_env
//
// Q-Channel 한 채널을 감싸는 env. 상위(테스트/상위 env)에서 해야 할 일을
// "cfg 하나 넘기고, sequencer 핸들 쓰기" 로 줄이는 것이 목적이다.
//
// 상위가 하지 않아도 되는 것:
//   - agent / monitor / driver / sequencer / coverage 생성
//   - config_db 에 "cfg" 와 "vif" 를 경로 맞춰 넣기 (env 가 자기 subtree 로 내려보낸다)
//   - monitor 의 analysis port 를 찾아 들어가기 (env.ap 로 올려둔다)
//
// 상위가 하는 것:
//   1. qch_config 를 만들어 role 과 vif 를 채운다
//   2. env 를 만들고 cfg 를 준다 (핸들 직접 대입 또는 config_db)
//   3. run_phase 에서 env.ctrl_seqr / rsp_seqr / act_seqr 에 시퀀스를 올린다
//
// 채널이 두 개면 env 를 두 개 만든다. 각 env 가 자기 cfg.vif 를 자기 subtree 에만
// 내려보내므로 서로 섞이지 않는다.
// ---------------------------------------------------------------------------
class qch_env extends uvm_env;

  `uvm_component_utils(qch_env)

  qch_config cfg;
  qch_agent  agent;

  // -------------------------------------------------------------------------
  // 상위가 쓰는 핸들
  //
  // connect_phase 에서 채운다. build_phase 에서는 채울 수 없다 — agent 의
  // sequencer 는 agent 의 build_phase 에서 만들어지고, 그것은 env 의
  // build_phase 보다 나중이다. connect_phase 는 bottom-up 이라
  // agent.connect -> env.connect -> 상위.connect 순서가 보장된다.
  //
  // role 에 따라 일부는 null 로 남는다:
  //   CONTROLLER : ctrl_seqr 만
  //   DEVICE     : rsp_seqr, act_seqr
  //   PASSIVE    : 없음 (ap 만)
  // -------------------------------------------------------------------------
  qch_controller_sequencer      ctrl_seqr;
  qch_device_response_sequencer rsp_seqr;
  qch_device_active_sequencer   act_seqr;

  // 상위 scoreboard 가 붙는 자리. monitor 의 port 를 그대로 올린 것이다.
  uvm_analysis_port #(qch_monitor_item) ap;

  function new(string name = "qch_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    virtual qch_if vif_from_db;

    super.build_phase(phase);

    // cfg 를 얻는 두 경로를 모두 허용한다.
    //   (a) 상위 build_phase 에서 env.cfg 에 직접 대입   ← 가장 간단
    //   (b) config_db 로 전달
    // (a) 가 되는 이유: build_phase 는 top-down 이므로 상위가 env 를 만든 뒤
    // 핸들을 대입하는 시점이 env 의 build_phase 보다 앞이다.
    if (cfg == null)
      if (!uvm_config_db#(qch_config)::get(this, "", "cfg", cfg))
        `uvm_fatal(get_type_name(),
                   "qch_config 가 없다. 상위에서 env.cfg 에 대입하거나 config_db 로 넘겨야 한다")

    // vif 도 두 경로를 허용한다. cfg.vif 가 비어 있으면 config_db 에서 찾아
    // cfg 에 채워 넣는다 (이후 참조가 한 곳으로 모이도록).
    if (cfg.vif == null)
      if (uvm_config_db#(virtual qch_if)::get(this, "", "vif", vif_from_db))
        cfg.vif = vif_from_db;

    if (cfg.vif == null)
      `uvm_fatal(get_type_name(),
                 "qch_if 핸들이 없다. cfg.vif 에 대입하거나 이 env 경로에 \"vif\" 를 set 해야 한다")

    // 이 env 의 subtree 에만 내려보낸다. 전역 "*" 로 뿌리지 않는 이유는
    // 채널이 여러 개일 때 서로 덮어쓰기 때문이다.
    uvm_config_db#(qch_config)::set(this, "*", "cfg", cfg);
    uvm_config_db#(virtual qch_if)::set(this, "*", "vif", cfg.vif);

    agent = qch_agent::type_id::create("agent", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    ap = agent.mon.ap;

    case (cfg.role)
      QCH_ROLE_CONTROLLER: ctrl_seqr = agent.ctrl_seqr;
      QCH_ROLE_DEVICE: begin
        rsp_seqr = agent.rsp_seqr;
        act_seqr = agent.act_seqr;
      end
      QCH_ROLE_PASSIVE: ;  // sequencer 없음
    endcase
  endfunction

endclass
