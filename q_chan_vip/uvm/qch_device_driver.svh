// ---------------------------------------------------------------------------
// qch_device_driver
//
// QACCEPTn / QDENY / QACTIVE 를 구동한다.
//
// 세 프로세스가 독립적으로 돈다:
//   response_loop : QREQn 하강에 대해 아이템의 accept/deny 정책을 적용
//   exit_loop     : QREQn 이 HIGH 로 돌아오면 QACCEPTn 을 올리거나 QDENY 를 내림
//   active_loop   : QACTIVE 아이템을 처리 (handshake 와 무관)
//
// response_loop 와 active_loop 는 서로 다른 sequencer 에서 아이템을 받는다.
// 같은 sequencer 를 쓰면 응답 대기 중에 QACTIVE 가 막힌다.
//
// 이 증분은 트랜잭션 도중 리셋을 지원하지 않는다.
// ---------------------------------------------------------------------------
class qch_device_driver extends uvm_driver #(qch_device_response_item);

  `uvm_component_utils(qch_device_driver)

  // 기본 seq_item_port 는 응답 아이템용이고, QACTIVE 용 포트를 따로 둔다.
  uvm_seq_item_pull_port #(qch_device_active_item) act_seq_item_port;

  virtual qch_if.device vif;
  qch_config            cfg;

  function new(string name = "qch_device_driver", uvm_component parent = null);
    super.new(name, parent);
    act_seq_item_port = new("act_seq_item_port", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    virtual qch_if raw_vif;
    super.build_phase(phase);
    if (!uvm_config_db#(virtual qch_if)::get(this, "", "vif", raw_vif))
      `uvm_fatal(get_type_name(), "virtual interface 'vif' not set in config_db")
    vif = raw_vif;
    if (!uvm_config_db#(qch_config)::get(this, "", "cfg", cfg))
      `uvm_fatal(get_type_name(), "qch_config 'cfg' not set in config_db")
  endfunction

  virtual task run_phase(uvm_phase phase);
    // IHI0068D 2.1.2: "At reset assertion, a device must drive both QACCEPTn
    // and QDENY LOW." QACTIVE 는 LOW/HIGH 둘 다 허용되며, 시작 시 할 일이 없으면
    // LOW 가 권장된다.
    vif.QACCEPTn <= 1'b0;
    vif.QDENY    <= 1'b0;
    vif.QACTIVE  <= 1'b0;

    wait (vif.rst_n === 1'b1);
    @(posedge vif.clk);

    fork
      response_loop();
      exit_loop();
      active_loop();
    join
  endtask

  // QREQn 하강에 대한 응답. 아이템을 엣지 전에 미리 확보한다 — 엣지 후에
  // 시퀀스를 기다리면 response_delay_cycles 가 의미를 잃는다.
  //
  // qch_device_response_item 의 pre_delay_cycles 는 여기서 무시한다. 이 아이템은
  // 즉시 구동형이 아니라 QREQn 하강을 기다리는 반응형이라 "구동 전 대기" 의
  // 기준점이 없다. 지연은 response_delay_cycles 하나만 쓴다.
  local task response_loop();
    qch_device_response_item req;

    forever begin
      seq_item_port.get_next_item(req);

      @(negedge vif.QREQn);

      repeat (req.response_delay_cycles) @(posedge vif.clk);

      if (req.policy == QCH_ACCEPT) vif.QACCEPTn <= 1'b0;
      else                          vif.QDENY    <= 1'b1;

      @(posedge vif.clk);
      seq_item_port.item_done();
    end
  endtask

  // QREQn 이 HIGH 인데 아직 Q_RUN 이 아니면 되돌린다.
  //   Q_EXIT     (QACCEPTn LOW) -> QACCEPTn 을 HIGH 로
  //   Q_CONTINUE (QDENY HIGH)   -> QDENY 를 LOW 로
  //
  // 이 두 엣지는 아이템 정책의 대상이 아니다. handshake rules 상 device 에게
  // 선택지가 없고, controller 가 QREQn 을 올린 뒤에만 가능하기 때문이다.
  // 따라서 타이밍만 config 로 준다.
  //
  // 리셋에서 QREQn HIGH 로 나온 경우(Q_EXIT)도 이 루프가 그대로 처리한다.
  local task exit_loop();
    forever begin
      @(posedge vif.clk);
      if (vif.QREQn === 1'b1 && (vif.QACCEPTn === 1'b0 || vif.QDENY === 1'b1)) begin
        repeat (cfg.exit_delay_cycles) @(posedge vif.clk);
        if (vif.QACCEPTn === 1'b0) vif.QACCEPTn <= 1'b1;
        if (vif.QDENY    === 1'b1) vif.QDENY    <= 1'b0;
      end
    end
  endtask

  // QACTIVE 는 handshake 와 완전히 독립이므로 별도 sequencer 에서 받는다.
  local task active_loop();
    qch_device_active_item req;

    forever begin
      act_seq_item_port.get_next_item(req);
      repeat (req.pre_delay_cycles) @(posedge vif.clk);
      vif.QACTIVE <= (req.action == QCH_ACTIVE_HIGH) ? 1'b1 : 1'b0;
      @(posedge vif.clk);
      act_seq_item_port.item_done();
    end
  endtask

endclass
