// ---------------------------------------------------------------------------
// qch_multi_config / qch_multi_env
//
// Q-Channel 이 여러 개일 때 쓰는 상위 컨테이너.
//
// 채널마다 qch_env 를 하나씩 두는 구조는 유지한다. cfg 와 vif 를 env subtree 로만
// 내려보내는 격리가 채널이 섞이지 않는 근거이고, 그것을 포기하면 안 된다.
// 이 컨테이너가 하는 일은 그 env 들을 대신 만들어서 테스트의 반복 코드를 없애는
// 것과, 채널을 넘나드는 시퀀스가 올라갈 virtual sequencer 를 붙이는 것이다.
//
// 테스트가 쓰는 모습:
//
//   mcfg = qch_multi_config::type_id::create("mcfg");
//   void'(mcfg.add("cpu",  QCH_ROLE_CONTROLLER, vif_cpu ));
//   void'(mcfg.add("l2",   QCH_ROLE_CONTROLLER, vif_l2  ));
//   void'(mcfg.add("crmu", QCH_ROLE_DEVICE,     vif_crmu));
//   menv     = qch_multi_env::type_id::create("menv", this);
//   menv.cfg = mcfg;
//   ...
//   vseq.start(menv.vseqr);          // 채널 넘나드는 시퀀스
//   seq.start(menv.get_ctrl("cpu")); // 한 채널만
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// qch_multi_config : 채널 이름 -> qch_config
// ---------------------------------------------------------------------------
class qch_multi_config extends uvm_object;

  `uvm_object_utils(qch_multi_config)

  qch_config ch[string];

  // 등록 순서 보존. 연관 배열 순회는 사전순이라 전력 시퀀스 순서로 쓸 수 없다.
  string names[$];

  function new(string name = "qch_multi_config");
    super.new(name);
  endfunction

  // 채널을 하나 등록하고 그 cfg 를 돌려준다. 반환값으로 세부 설정을 이어서 만진다:
  //   c = mcfg.add("cpu", QCH_ROLE_CONTROLLER, vif_cpu);
  //   c.reset_qreqn_high = 0;
  function qch_config add(string ch_name, qch_role_e role_arg, virtual qch_if vif_arg);
    qch_config c;

    if (ch.exists(ch_name))
      `uvm_fatal(get_type_name(), $sformatf("채널 이름 '%s' 가 중복됐다", ch_name))
    if (vif_arg == null)
      `uvm_fatal(get_type_name(), $sformatf("채널 '%s' 의 qch_if 핸들이 null 이다", ch_name))

    c      = qch_config::type_id::create({"cfg_", ch_name});
    c.role = role_arg;
    c.vif  = vif_arg;

    ch[ch_name] = c;
    names.push_back(ch_name);
    return c;
  endfunction

endclass

// ---------------------------------------------------------------------------
// qch_multi_env : 채널 수만큼 qch_env 를 만들고 virtual sequencer 를 채운다
// ---------------------------------------------------------------------------
class qch_multi_env extends uvm_env;

  `uvm_component_utils(qch_multi_env)

  qch_multi_config      cfg;
  qch_env               envs[string];
  qch_virtual_sequencer vseqr;

  function new(string name = "qch_multi_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    string nm;

    super.build_phase(phase);

    if (cfg == null)
      if (!uvm_config_db#(qch_multi_config)::get(this, "", "cfg", cfg))
        `uvm_fatal(get_type_name(),
                   "qch_multi_config 가 없다. 상위에서 menv.cfg 에 대입하거나 config_db 로 넘겨야 한다")

    if (cfg.names.size() == 0)
      `uvm_fatal(get_type_name(), "등록된 채널이 없다 (qch_multi_config::add 호출 확인)")

    // build_phase 는 top-down 이므로 여기서 대입해도 각 env 의 build_phase 보다 앞이다.
    foreach (cfg.names[i]) begin
      nm           = cfg.names[i];
      envs[nm]     = qch_env::type_id::create({"env_", nm}, this);
      envs[nm].cfg = cfg.ch[nm];
    end

    vseqr = qch_virtual_sequencer::type_id::create("vseqr", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    string nm;

    super.connect_phase(phase);

    // connect_phase 는 bottom-up 이므로 각 env 의 sequencer 핸들은 이미 채워져 있다.
    vseqr.names = cfg.names;

    foreach (cfg.names[i]) begin
      nm = cfg.names[i];
      case (cfg.ch[nm].role)
        QCH_ROLE_CONTROLLER: vseqr.ctrl[nm] = envs[nm].ctrl_seqr;
        QCH_ROLE_DEVICE: begin
          vseqr.rsp[nm] = envs[nm].rsp_seqr;
          vseqr.act[nm] = envs[nm].act_seqr;
        end
        QCH_ROLE_PASSIVE: ;  // sequencer 없음
      endcase
    end
  endfunction

  // --- 편의 접근자 -------------------------------------------------------
  // 테스트가 envs[...] 를 직접 뒤지지 않도록.

  function qch_env get_env(string ch_name);
    if (!envs.exists(ch_name))
      `uvm_fatal(get_type_name(),
                 $sformatf("채널 '%s' 가 없다 (등록된 채널: %p)", ch_name, cfg.names))
    return envs[ch_name];
  endfunction

  function qch_controller_sequencer get_ctrl(string ch_name);
    return vseqr.get_ctrl(ch_name);
  endfunction

  function qch_device_response_sequencer get_rsp(string ch_name);
    return vseqr.get_rsp(ch_name);
  endfunction

  function qch_device_active_sequencer get_act(string ch_name);
    return vseqr.get_act(ch_name);
  endfunction

  // 채널의 monitor analysis port. 상위 scoreboard 가 붙는 자리.
  function uvm_analysis_port #(qch_monitor_item) get_ap(string ch_name);
    return get_env(ch_name).ap;
  endfunction

endclass
