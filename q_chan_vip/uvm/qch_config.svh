// ---------------------------------------------------------------------------
// qch_config : agent 의 역할과 타이밍 설정
// ---------------------------------------------------------------------------

typedef enum bit [1:0] {
  QCH_ROLE_CONTROLLER,  // QREQn 을 구동한다
  QCH_ROLE_DEVICE,      // QACCEPTn / QDENY / QACTIVE 를 구동한다
  QCH_ROLE_PASSIVE      // 아무것도 구동하지 않고 관찰만 한다
} qch_role_e;

class qch_config extends uvm_object;

  // 기본값을 PASSIVE 로 두는 이유: 설정을 깜빡했을 때 아무 신호도 구동하지
  // 않는 쪽이 안전하다. 실수로 DUT 신호와 충돌하는 것보다 낫다.
  qch_role_e   role                = QCH_ROLE_PASSIVE;

  // DEVICE 역할에서만 의미 있음. 1 이면 agent 가 응답 시퀀스를 자동으로 올린다.
  bit          start_responder_seq = 1'b1;

  // CONTROLLER 역할에서만 의미 있음. IHI0068D 2.1.2 는 리셋 해제 시점의 QREQn 을
  // LOW(Q_STOPPED) 또는 HIGH(Q_EXIT) 중 하나로 고르도록 허용한다. 둘 다 합법이다.
  bit          reset_qreqn_high    = 1'b1;

  // DEVICE 역할에서만 의미 있음. QREQn 이 HIGH 로 되돌아온 뒤 QACCEPTn 을 올리거나
  // QDENY 를 내리기까지의 지연. 이 두 엣지는 device 에게 선택지가 없어 아이템
  // 정책의 대상이 아니므로 타이밍만 여기서 준다.
  int unsigned exit_delay_cycles   = 0;

  `uvm_object_utils_begin(qch_config)
    `uvm_field_enum(qch_role_e, role,    UVM_ALL_ON)
    `uvm_field_int (start_responder_seq, UVM_ALL_ON | UVM_BIN)
    `uvm_field_int (reset_qreqn_high,    UVM_ALL_ON | UVM_BIN)
    `uvm_field_int (exit_delay_cycles,   UVM_ALL_ON | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "qch_config");
    super.new(name);
  endfunction

endclass
