// ---------------------------------------------------------------------------
// qch_controller_driver
//
// QREQn 만 구동한다.
//
// 이 증분은 트랜잭션 도중 리셋을 지원하지 않는다. 리셋 해제를 한 번 기다린 뒤
// 아이템 루프에 들어간다.
// ---------------------------------------------------------------------------
class qch_controller_driver extends uvm_driver #(qch_controller_item);

  `uvm_component_utils(qch_controller_driver)

  virtual qch_if.controller vif;
  qch_config                cfg;

  function new(string name = "qch_controller_driver", uvm_component parent = null);
    super.new(name, parent);
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
    qch_controller_item req;

    // IHI0068D 2.1.2: controller 는 리셋 해제 시점의 QREQn 을 LOW(Q_STOPPED) 또는
    // HIGH(Q_EXIT) 중 하나로 고를 수 있다. 둘 다 합법이므로 config 로 받는다.
    vif.QREQn <= cfg.reset_qreqn_high;

    wait (vif.rst_n === 1'b1);
    @(posedge vif.clk);

    forever begin
      seq_item_port.get_next_item(req);
      drive_one(req);
      seq_item_port.item_done();
    end
  endtask

  local task drive_one(qch_controller_item req);
    int unsigned elapsed;
    bit          done;

    repeat (req.pre_delay_cycles) @(posedge vif.clk);

    vif.QREQn <= (req.action == QCH_REQUEST_QUIESCENCE) ? 1'b0 : 1'b1;
    @(posedge vif.clk);

    elapsed               = 0;
    done                  = 1'b0;
    req.observed_response = QCH_RSP_NONE;

    // 스펙은 device 응답 시간의 상한을 정의하지 않는다. timeout 은 무한 대기를
    // 피하려는 시험 편의상의 장치이며, timeout 자체는 프로토콜 위반이 아니므로
    // uvm_error 를 내지 않는다. 위반 판정은 SVA 몫이다.
    while (!done && elapsed < req.response_timeout_cycles) begin
      if (req.action == QCH_REQUEST_QUIESCENCE) begin
        if (vif.QACCEPTn === 1'b0) begin
          req.observed_response = QCH_RSP_ACCEPTED;
          done                  = 1'b1;
        end
        else if (vif.QDENY === 1'b1) begin
          req.observed_response = QCH_RSP_DENIED;
          done                  = 1'b1;
        end
      end
      else begin
        // ALLOW_RUN 은 Q_RUN 도달을 기다린다.
        // 이 결과에 QCH_RSP_ACCEPTED 를 재사용하는 것은 정확한 표현이 아니다.
        // action 필드와 같이 봐야 의미가 확정된다. enum 확장은 소비자(커버리지/
        // 스코어보드)가 생길 때 함께 한다.
        if (vif.QACCEPTn === 1'b1 && vif.QDENY === 1'b0) begin
          req.observed_response = QCH_RSP_ACCEPTED;
          done                  = 1'b1;
        end
      end

      if (!done) begin
        @(posedge vif.clk);
        elapsed++;
      end
    end

    if (!done) req.observed_response = QCH_RSP_TIMEOUT;
    req.response_latency_cycles = elapsed;
  endtask

endclass
