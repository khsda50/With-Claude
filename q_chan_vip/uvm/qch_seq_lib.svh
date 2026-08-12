// ---------------------------------------------------------------------------
// qch_seq_lib
//
// 상위에서 바로 올릴 수 있는 controller 측 시퀀스. 지금까지 controller 시퀀스는
// 테스트 파일 안에만 있어서(qch_ctrl_smoke_seq, qch_loopback_seq) 다른 환경에서
// 재사용할 수 없었다. env 를 붙여 쓰려면 패키지 안에 하나는 있어야 한다.
//
// Device 측은 필요 없다. agent 가 cfg.start_responder_seq 로 qch_responder_seq 를
// 자동으로 올린다.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// qch_quiesce_seq : quiescence 요청 → 해제 왕복을 num_rounds 회 반복
//
// 요청 뒤에 항상 ALLOW_RUN 을 붙이는 것은 프로토콜 때문이다. IHI0068D 는 QDENY 가
// QREQn 이 HIGH 로 되돌아온 뒤에만 LOW 로 내려갈 수 있다고 정한다. 즉 거부되었을
// 때 요청을 되돌리는 것은 선택이 아니라 의무다. 수락된 경우도 Q_STOPPED ->
// Q_EXIT -> Q_RUN 으로 돌아오는 정상 경로라, 두 경우 모두 같은 모양이 된다.
// ---------------------------------------------------------------------------
class qch_quiesce_seq extends uvm_sequence #(qch_controller_item);

  `uvm_object_utils(qch_quiesce_seq)

  rand int unsigned num_rounds;

  // ALLOW_RUN 아이템의 pre_delay. Q_STOPPED / Q_DENIED 에 머무는 시간이 된다.
  rand int unsigned hold_cycles;

  // 다음 요청까지의 간격. Q_RUN 체류 시간이 되고, 커버리지의
  // cp_run_before_req 에 그대로 반영된다.
  rand int unsigned gap_cycles;

  constraint c_rounds { soft num_rounds  inside {[1:10]}; }
  constraint c_hold   { soft hold_cycles inside {[0:20]}; }
  constraint c_gap    { soft gap_cycles  inside {[0:20]}; }

  // 관측 결과 집계. 상위가 읽어 판정에 쓸 수 있다.
  int unsigned n_accepted;
  int unsigned n_denied;
  int unsigned n_timeout;

  function new(string name = "qch_quiesce_seq");
    super.new(name);
  endfunction

  virtual task body();
    qch_controller_item req;

    n_accepted = 0;
    n_denied   = 0;
    n_timeout  = 0;

    repeat (num_rounds) begin
      // 1) quiescence 요청 — driver 가 응답 또는 timeout 까지 블록한다
      req = qch_controller_item::type_id::create("req_quiesce");
      start_item(req);
      if (!req.randomize() with { action           == QCH_REQUEST_QUIESCENCE;
                                  pre_delay_cycles == local::gap_cycles; })
        `uvm_error(get_type_name(), "randomize() failed (REQUEST_QUIESCENCE)")
      finish_item(req);

      case (req.observed_response)
        QCH_RSP_ACCEPTED : n_accepted++;
        QCH_RSP_DENIED   : n_denied++;
        QCH_RSP_TIMEOUT  : n_timeout++;
        default          : ;
      endcase

      // 2) 요청 해제 — 거부된 경우에는 의무, 수락된 경우에는 정상 복귀 경로
      req = qch_controller_item::type_id::create("req_release");
      start_item(req);
      if (!req.randomize() with { action           == QCH_ALLOW_RUN;
                                  pre_delay_cycles == local::hold_cycles; })
        `uvm_error(get_type_name(), "randomize() failed (ALLOW_RUN)")
      finish_item(req);
    end

    `uvm_info(get_type_name(),
              $sformatf("%0d rounds: accepted=%0d denied=%0d timeout=%0d",
                        num_rounds, n_accepted, n_denied, n_timeout), UVM_LOW)
  endtask

endclass
