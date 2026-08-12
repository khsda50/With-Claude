// ---------------------------------------------------------------------------
// qch_seq_lib
//
// 재사용 시퀀스 모음. 지금까지 controller 시퀀스가 테스트 파일 안에만 있어
// (qch_ctrl_smoke_seq, qch_loopback_seq, qch_fixed_delay_seq) 다른 환경에서
// 쓸 수 없었다. 여기로 옮기고 공통 부분을 base 로 뺀다.
//
// 세 갈래로 나뉜다. 갈래가 sequencer 를 결정한다.
//   controller 측      : qch_controller_item      -> ctrl_seqr
//   device 응답 측     : qch_device_response_item -> rsp_seqr
//   device QACTIVE 측  : qch_device_active_item   -> act_seqr
//
// `randomize() with {}` 안에서 local:: 을 쓰지 않는다. 인자와 멤버 이름을 아이템
// 필드와 겹치지 않게 지어(act_arg, delay_arg, timeout_cycles ...) 평범한 이름
// 해석으로 충분하게 만들었다. local:: 지원이 툴마다 미묘한 것을 피하려는 것이다.
// ---------------------------------------------------------------------------

// ===========================================================================
// Controller 측
// ===========================================================================

// ---------------------------------------------------------------------------
// qch_ctrl_base_seq : 요청/해제 한 번을 보내는 공통 동작
//
// 세 시퀀스가 똑같이 반복하던 create -> start_item -> randomize -> finish_item ->
// 결과 집계를 여기로 모았다. 상속해서 body() 만 쓰면 된다.
// ---------------------------------------------------------------------------
class qch_ctrl_base_seq extends uvm_sequence #(qch_controller_item);

  `uvm_object_utils(qch_ctrl_base_seq)

  // 아이템에 실을 응답 대기 상한. 스펙은 device 응답 시간에 상한을 두지 않으므로
  // 이것은 무한 대기를 피하려는 시험 편의값이다.
  int unsigned timeout_cycles = 200;

  // 관측 결과 집계. 상위가 판정에 쓸 수 있다.
  int unsigned n_accepted;
  int unsigned n_denied;
  int unsigned n_timeout;

  // 보낸 아이템 보관. 아이템 필드를 직접 검사하는 테스트만 켠다.
  bit                 keep_sent = 1'b0;
  qch_controller_item sent[$];

  function new(string name = "qch_ctrl_base_seq");
    super.new(name);
  endfunction

  // 고정 지연으로 하나 보낸다.
  protected task send(qch_req_action_e act_arg, int unsigned delay_arg);
    qch_controller_item req;
    req = qch_controller_item::type_id::create("req");
    start_item(req);
    if (!req.randomize() with { action                  == act_arg;
                                pre_delay_cycles        == delay_arg;
                                response_timeout_cycles == timeout_cycles; })
      `uvm_error(get_type_name(), $sformatf("randomize() failed (%s)", act_arg.name()))
    finish_item(req);
    collect(req);
  endtask

  // 지연을 범위 안에서 뽑아 하나 보낸다.
  protected task send_rand(qch_req_action_e act_arg,
                           int unsigned     lo_arg,
                           int unsigned     hi_arg);
    qch_controller_item req;
    req = qch_controller_item::type_id::create("req");
    start_item(req);
    if (!req.randomize() with { action                  == act_arg;
                                pre_delay_cycles        inside {[lo_arg:hi_arg]};
                                response_timeout_cycles == timeout_cycles; })
      `uvm_error(get_type_name(), $sformatf("randomize() failed (%s)", act_arg.name()))
    finish_item(req);
    collect(req);
  endtask

  protected function void collect(qch_controller_item req);
    if (keep_sent) sent.push_back(req);
    case (req.observed_response)
      QCH_RSP_ACCEPTED : n_accepted++;
      QCH_RSP_DENIED   : n_denied++;
      QCH_RSP_TIMEOUT  : n_timeout++;
      default          : ;
    endcase
  endfunction

  // 한 왕복 = quiescence 요청 + 해제.
  //
  // 해제를 항상 붙이는 것은 프로토콜 때문이다. IHI0068D 는 QDENY 가 QREQn 이
  // HIGH 로 되돌아온 뒤에만 LOW 로 내려갈 수 있다고 정하므로, 거부되었을 때
  // 요청을 되돌리는 것은 선택이 아니라 의무다. 수락된 경우도
  // Q_STOPPED -> Q_EXIT -> Q_RUN 정상 복귀 경로라 두 경우가 같은 모양이 된다.
  protected task round(int unsigned gap_arg, int unsigned hold_arg);
    send(QCH_REQUEST_QUIESCENCE, gap_arg);
    send(QCH_ALLOW_RUN,          hold_arg);
  endtask

  virtual task body();
    round(0, 0);
  endtask

endclass

// ---------------------------------------------------------------------------
// qch_quiesce_seq : 왕복을 num_rounds 회 반복. 일반 회귀용.
//
// gap_cycles 는 Q_RUN 체류, hold_cycles 는 Q_STOPPED / Q_DENIED 체류가 되어
// 커버리지의 cp_run_before_req / cp_stopped_dwell 에 그대로 반영된다.
// ---------------------------------------------------------------------------
class qch_quiesce_seq extends qch_ctrl_base_seq;

  `uvm_object_utils(qch_quiesce_seq)

  rand int unsigned num_rounds;
  rand int unsigned hold_cycles;
  rand int unsigned gap_cycles;

  constraint c_rounds { soft num_rounds  inside {[1:10]}; }
  constraint c_hold   { soft hold_cycles inside {[0:20]}; }
  constraint c_gap    { soft gap_cycles  inside {[0:20]}; }

  function new(string name = "qch_quiesce_seq");
    super.new(name);
  endfunction

  virtual task body();
    repeat (num_rounds) round(gap_cycles, hold_cycles);
    `uvm_info(get_type_name(),
              $sformatf("%0d rounds: accepted=%0d denied=%0d timeout=%0d",
                        num_rounds, n_accepted, n_denied, n_timeout), UVM_LOW)
  endtask

endclass

// ---------------------------------------------------------------------------
// qch_ctrl_smoke_seq : 왕복 1 회. driver 단위 테스트가 아이템 필드를 직접
// 검사하므로 keep_sent 를 켜고 timeout 을 100 으로 둔다.
// ---------------------------------------------------------------------------
class qch_ctrl_smoke_seq extends qch_ctrl_base_seq;

  `uvm_object_utils(qch_ctrl_smoke_seq)

  function new(string name = "qch_ctrl_smoke_seq");
    super.new(name);
    timeout_cycles = 100;
    keep_sent      = 1'b1;
  endfunction

  virtual task body();
    send(QCH_REQUEST_QUIESCENCE, 2);
    send(QCH_ALLOW_RUN,          0);
  endtask

endclass

// ---------------------------------------------------------------------------
// qch_loopback_seq : 왕복 n_rounds 회, 지연을 0~5 에서 뽑는다.
// VIP 끼리 마주보게 붙인 loopback 테스트용.
// ---------------------------------------------------------------------------
class qch_loopback_seq extends qch_ctrl_base_seq;

  `uvm_object_utils(qch_loopback_seq)

  int unsigned n_rounds = 20;

  function new(string name = "qch_loopback_seq");
    super.new(name);
  endfunction

  virtual task body();
    repeat (n_rounds) begin
      send_rand(QCH_REQUEST_QUIESCENCE, 0, 5);
      send_rand(QCH_ALLOW_RUN,          0, 5);
    end
  endtask

endclass

// ===========================================================================
// Device 응답 측
//
// 기본 응답 시퀀스(qch_responder_seq)는 agent 가 자동으로 올리므로 별도 파일에
// 있다. 여기 있는 것은 특정 시나리오를 몰 때 cfg.start_responder_seq = 0 으로
// 두고 직접 올리는 것들이다.
//
// 아래 응답/QACTIVE 시퀀스는 모두 forever 다. 요청이 언제 올지 모르는 쪽이라
// 끝나는 지점이 없다. 반드시 fork ... join_none 으로 올리고 objection 을 걸지
// 않는다. 그냥 start 하면 테스트가 그 자리에서 멈춘다.
//
//   fork dly_seq.start(env.rsp_seqr); join_none
// ===========================================================================

// ---------------------------------------------------------------------------
// qch_fixed_delay_seq : 항상 수락 + 고정 응답 지연. 지연이 실제로 반영되는지
// 확인하거나, 커버리지의 특정 latency bin 을 겨냥할 때 쓴다.
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

// ---------------------------------------------------------------------------
// qch_deny_seq : 항상 거부. deny 경로를 강제로 밟게 한다.
//
// 커버리지 hole 을 메우는 용도다. 기본 응답 시퀀스는 accept/deny 를 50:50 으로
// 뽑으므로 특정 지연 구간의 deny 조합(x_response_latency 의 denied x medium 등)이
// 남기 쉽다. 지연 범위를 좁혀 이 시퀀스를 돌리면 그 칸을 겨냥할 수 있다.
// ---------------------------------------------------------------------------
class qch_deny_seq extends uvm_sequence #(qch_device_response_item);

  `uvm_object_utils(qch_deny_seq)

  rand int unsigned delay_lo;
  rand int unsigned delay_hi;

  constraint c_range { soft delay_lo == 0; soft delay_hi == 20; delay_lo <= delay_hi; }

  function new(string name = "qch_deny_seq");
    super.new(name);
  endfunction

  virtual task body();
    qch_device_response_item req;
    forever begin
      req = qch_device_response_item::type_id::create("deny_req");
      start_item(req);
      if (!req.randomize() with { policy                == QCH_DENY;
                                  response_delay_cycles inside {[delay_lo:delay_hi]}; })
        `uvm_error(get_type_name(), "randomize() failed on deny item")
      finish_item(req);
    end
  endtask

endclass

// ===========================================================================
// Device QACTIVE 측
//
// 지금까지 이 sequencer(act_seqr)를 쓰는 시퀀스가 없었다. QACTIVE 를 흔들지
// 않으면 커버리지의 cp_qactive 와 x_response_qactive 가 절반만 찬다.
// ===========================================================================

// ---------------------------------------------------------------------------
// qch_active_toggle_seq : QACTIVE 를 무작위 간격으로 토글한다.
//
// IHI0068D 2.1.1 은 QACTIVE 전이가 QREQn / QACCEPTn / QDENY 값에 제약받지 않는다고
// 정한다. 그래서 handshake 와 무관하게 계속 돌려도 된다. 이 독립성이 아이템
// 설계에서 QACTIVE 를 별도 아이템으로 뺀 이유이기도 하다.
// ---------------------------------------------------------------------------
class qch_active_toggle_seq extends uvm_sequence #(qch_device_active_item);

  `uvm_object_utils(qch_active_toggle_seq)

  rand int unsigned gap_lo;
  rand int unsigned gap_hi;

  // 상한을 20 으로 두는 이유: qch_base_item 의 pre_delay_cycles 에
  // soft pre_delay_cycles inside {[0:20]} 가 걸려 있다. soft 제약은 하드 제약과
  // 충돌할 때만 물러나므로, 여기서 [1:30] 을 걸면 겹치는 [1:20] 안에서만 뽑혀
  // 20 을 넘는 값이 나오지 않는다. 더 긴 간격이 필요하면 아이템의 soft 제약을
  // 끄고(constraint_mode) 써야 한다.
  constraint c_gap { soft gap_lo == 1; soft gap_hi == 20; gap_lo <= gap_hi; }

  function new(string name = "qch_active_toggle_seq");
    super.new(name);
  endfunction

  virtual task body();
    qch_device_active_item req;
    forever begin
      req = qch_device_active_item::type_id::create("act_req");
      start_item(req);
      if (!req.randomize() with { pre_delay_cycles inside {[gap_lo:gap_hi]}; })
        `uvm_error(get_type_name(), "randomize() failed on active item")
      finish_item(req);
    end
  endtask

endclass
