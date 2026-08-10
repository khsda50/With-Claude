// ---------------------------------------------------------------------------
// qch_item_pkg
//
// AMBA Low Power Interface(IHI0068D) Q-Channel VIP 의 sequence_item 정의.
//
// Q-Channel 에는 역할이 다른 두 주체가 있다:
//   Controller : QREQn 을 구동 (quiescence 요청)
//   Device     : QACCEPTn / QDENY / QACTIVE 를 구동
// 두 역할이 구동하는 신호와 의사결정의 폭이 다르므로 role 별로 아이템을 나눈다.
//
// 이 아이템들은 순수하게 "자극(의도)" 표현용이다. 프로토콜 합법성 검사
// (예: deny 이후 controller 가 QREQn 을 되돌려야 한다)는 여기서 강제하지 않고,
// 별도 증분의 재사용 SVA 체커가 담당한다. 의도적으로 위반하는 시퀀스도
// 만들 수 있어야 하기 때문이다.
// ---------------------------------------------------------------------------
package qch_item_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // -------------------------------------------------------------------------
  // enum
  //
  // label 에 QCH_ 접두사를 붙인 이유: 이 패키지는 import ...::* 로 쓰이므로
  // ACCEPT / DENY 같은 일반 명칭은 다른 VIP 패키지와 충돌할 수 있다.
  // -------------------------------------------------------------------------

  // Controller 가 QREQn 에 가하는 액션.
  // QREQn 은 active-LOW 라서 "assert" 라는 표현이 헷갈리므로 의미로 이름 짓는다.
  typedef enum bit {
    QCH_REQUEST_QUIESCENCE,  // QREQn 을 LOW 로 구동 (quiescence 요청)
    QCH_ALLOW_RUN            // QREQn 을 HIGH 로 구동 (운영 상태 허용)
  } qch_req_action_e;

  // Controller 가 요청 후 관측한 Device 의 응답.
  typedef enum bit [1:0] {
    QCH_RSP_NONE,      // 아직 응답 없음 / 해당 없음
    QCH_RSP_ACCEPTED,  // QACCEPTn LOW  (Q_STOPPED 진입)
    QCH_RSP_DENIED,    // QDENY HIGH    (Q_DENIED 진입)
    QCH_RSP_TIMEOUT    // timeout 안에 응답 없음
  } qch_ctrl_response_e;

  // Device 가 quiescence 요청 1회에 대해 취할 정책.
  //
  // "deny 했다가 나중에 스스로 accept" 는 프로토콜상 불가능하다. IHI0068D
  // handshake rules 에 따르면 QDENY 는 QREQn 이 HIGH 로 되돌아와야만 LOW 로
  // 내려갈 수 있다. 즉 deny 를 푸는 것은 controller 의 재요청을 반드시 거친다.
  // 따라서 아이템 하나는 ACCEPT/DENY 둘 중 하나만 고르면 충분하고,
  // deny-then-accept 시나리오는 controller 가 재요청하고 그때 새 아이템이
  // ACCEPT 를 고르는 두 라운드로 자연스럽게 표현된다.
  typedef enum bit {
    QCH_ACCEPT,  // QACCEPTn 을 LOW 로 구동 (Q_STOPPED 로 진행)
    QCH_DENY     // QDENY 를 HIGH 로 구동   (Q_DENIED 로 진행)
  } qch_device_policy_e;

  // Device 가 QACTIVE 에 가하는 액션.
  typedef enum bit {
    QCH_ACTIVE_HIGH,  // 수행할 작업이 있음을 표시
    QCH_ACTIVE_LOW    // 조용해질 수 있다는 힌트
  } qch_active_action_e;

  // -------------------------------------------------------------------------
  // 인터페이스 상태 (IHI0068D Table 2-1)
  // -------------------------------------------------------------------------
  typedef enum bit [2:0] {
    QCH_ST_RUN,       // QREQn=1, QACCEPTn=1, QDENY=0 : 운영 중
    QCH_ST_REQUEST,   // QREQn=0, QACCEPTn=1, QDENY=0 : 요청 받았으나 아직 운영 중
    QCH_ST_STOPPED,   // QREQn=0, QACCEPTn=0, QDENY=0 : 조용해짐
    QCH_ST_EXIT,      // QREQn=1, QACCEPTn=0, QDENY=0 : 깨어나는 중
    QCH_ST_DENIED,    // QREQn=0, QACCEPTn=1, QDENY=1 : 거부함
    QCH_ST_CONTINUE,  // QREQn=1, QACCEPTn=1, QDENY=1 : 거부에 대한 controller 응답
    QCH_ST_ILLEGAL    // QACCEPTn=0, QDENY=1 : Table 2-1 "Unused"
  } qch_state_e;

  // 신호 조합을 상태로 변환한다. monitor 와 테스트가 공유한다.
  function automatic qch_state_e qch_decode_state(bit qreqn, bit qacceptn, bit qdeny);
    if (qacceptn == 1'b0 && qdeny == 1'b1) return QCH_ST_ILLEGAL;
    case ({qreqn, qacceptn, qdeny})
      3'b110  : return QCH_ST_RUN;
      3'b010  : return QCH_ST_REQUEST;
      3'b000  : return QCH_ST_STOPPED;
      3'b100  : return QCH_ST_EXIT;
      3'b011  : return QCH_ST_DENIED;
      3'b111  : return QCH_ST_CONTINUE;
      default : return QCH_ST_ILLEGAL;
    endcase
  endfunction

  // -------------------------------------------------------------------------
  // 커버리지 어휘 (transition / device 응답)
  //
  // monitor 아이템은 (prev_state, state) 쌍으로 전이를 표현한다. 커버리지에서
  // 이것을 그대로 cross 하면 7x7=49 칸이 생기고 그중 7 개만 합법이라 지표가
  // 희석된다. 그래서 쌍을 "이름 있는 전이" 로 접어서 쓴다.
  //
  // 전이 판정을 covergroup 의 transition bin( A => B )으로 하지 않는 이유:
  // transition bin 은 연속된 두 번의 sample 사이의 이력에 의존한다. monitor 는
  // 리셋 중에 발행을 멈추므로, 리셋을 걸친 두 아이템이 인접 sample 로 들어오면
  // 실제로 일어나지 않은 전이가 하나 잡힌다. 아이템이 prev_state 를 이미 들고
  // 있으니 이력에 의존하지 않고 아이템 하나로 판정하는 편이 정확하다.
  // -------------------------------------------------------------------------

  // IHI0068D handshake 가 허용하는 전이 7 개 + 그 밖의 전부.
  typedef enum bit [3:0] {
    QCH_TRANS_RUN_REQ,    // Q_RUN      -> Q_REQUEST  : controller 가 요청
    QCH_TRANS_REQ_STOP,   // Q_REQUEST  -> Q_STOPPED  : device 가 수락
    QCH_TRANS_REQ_DENY,   // Q_REQUEST  -> Q_DENIED   : device 가 거부
    QCH_TRANS_STOP_EXIT,  // Q_STOPPED  -> Q_EXIT     : controller 가 요청 해제
    QCH_TRANS_EXIT_RUN,   // Q_EXIT     -> Q_RUN      : device 가 QACCEPTn 복귀
    QCH_TRANS_DENY_CONT,  // Q_DENIED   -> Q_CONTINUE : controller 가 요청 해제
    QCH_TRANS_CONT_RUN,   // Q_CONTINUE -> Q_RUN      : device 가 QDENY 해제
    QCH_TRANS_OTHER       // 위 7 개가 아닌 전이 (합법이 아니거나 리셋 경계)
  } qch_trans_e;

  // Q_REQUEST 를 떠나는 전이에서 읽어낸 device 의 답.
  //
  // qch_ctrl_response_e 와 별개로 두는 이유: 그쪽은 controller driver 가 자기가
  // 구동한 결과를 기록하는 자극 측 필드이고, 이쪽은 관측만으로 판정한 결과다.
  // PASSIVE 구성에서는 자극 아이템이 없으므로 커버리지는 이쪽만 쓸 수 있다.
  typedef enum bit [1:0] {
    QCH_OBS_ACCEPTED,  // Q_REQUEST -> Q_STOPPED
    QCH_OBS_DENIED,    // Q_REQUEST -> Q_DENIED
    QCH_OBS_OTHER      // 응답 없이 Q_REQUEST 를 떠남 (규칙 위반 → SVA 대상)
  } qch_obs_response_e;

  // 전이 쌍을 이름 있는 전이로 접는다.
  function automatic qch_trans_e qch_classify_trans(qch_state_e prev_state,
                                                    qch_state_e state);
    case (prev_state)
      QCH_ST_RUN      : if (state == QCH_ST_REQUEST)  return QCH_TRANS_RUN_REQ;
      QCH_ST_REQUEST  : begin
                          if (state == QCH_ST_STOPPED) return QCH_TRANS_REQ_STOP;
                          if (state == QCH_ST_DENIED)  return QCH_TRANS_REQ_DENY;
                        end
      QCH_ST_STOPPED  : if (state == QCH_ST_EXIT)     return QCH_TRANS_STOP_EXIT;
      QCH_ST_EXIT     : if (state == QCH_ST_RUN)      return QCH_TRANS_EXIT_RUN;
      QCH_ST_DENIED   : if (state == QCH_ST_CONTINUE) return QCH_TRANS_DENY_CONT;
      QCH_ST_CONTINUE : if (state == QCH_ST_RUN)      return QCH_TRANS_CONT_RUN;
      default         : ;
    endcase
    return QCH_TRANS_OTHER;
  endfunction

  // Q_REQUEST 를 떠나는 전이만 의미가 있다. 그 밖에서는 QCH_OBS_OTHER 를 돌려주고,
  // 커버리지 쪽에서 prev_state 로 걸러 샘플하지 않는다.
  function automatic qch_obs_response_e qch_classify_response(qch_state_e prev_state,
                                                              qch_state_e state);
    if (prev_state != QCH_ST_REQUEST) return QCH_OBS_OTHER;
    case (state)
      QCH_ST_STOPPED : return QCH_OBS_ACCEPTED;
      QCH_ST_DENIED  : return QCH_OBS_DENIED;
      default        : return QCH_OBS_OTHER;
    endcase
  endfunction

  // -------------------------------------------------------------------------
  // qch_base_item : 모든 Q-Channel 아이템의 공통 필드
  // -------------------------------------------------------------------------
  class qch_base_item extends uvm_sequence_item;

    // 아이템을 실제로 구동하기 전 대기 사이클.
    // 어느 클럭 기준인지는 driver/config 가 정한다 (아이템은 클럭을 모른다).
    rand int unsigned pre_delay_cycles;

    // soft 이므로 시퀀스에서 범위 밖 값으로 override 할 수 있다.
    constraint c_pre_delay { soft pre_delay_cycles inside {[0:20]}; }

    `uvm_object_utils_begin(qch_base_item)
      `uvm_field_int(pre_delay_cycles, UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "qch_base_item");
      super.new(name);
    endfunction

  endclass

  // -------------------------------------------------------------------------
  // qch_controller_item : QREQn 토글 1회 (primitive)
  //
  // Controller 가 구동하는 신호는 QREQn 한 비트뿐이다. deny 되었을 때 계속
  // 재시도할지 포기할지 같은 시나리오 구성은 상위 sequence 가 이 아이템을
  // 여러 개 엮어서 만든다.
  // -------------------------------------------------------------------------
  class qch_controller_item extends qch_base_item;

    rand qch_req_action_e action;

    // 스펙(IHI0068D)은 Device 응답 시간의 상한을 정의하지 않는다. 이 필드는
    // VIP 가 무한 대기에 빠지지 않게 하려는 시험 편의상의 값이다.
    // 나중에 agent config 가 생기면 그 기본값을 참조하도록 교체한다.
    rand int unsigned response_timeout_cycles;

    // 아래 두 필드는 driver 가 구동 후 채워 넣는 결과 필드다.
    // randomize() 대상이 아니며(rand 아님), 커버리지/디버그용이다.
    // 프로토콜 위반 판정은 이 필드의 책임이 아니다.
    qch_ctrl_response_e observed_response;
    int unsigned        response_latency_cycles;

    constraint c_timeout { soft response_timeout_cycles inside {[10:1000]}; }

    `uvm_object_utils_begin(qch_controller_item)
      `uvm_field_enum(qch_req_action_e,    action,                  UVM_ALL_ON)
      `uvm_field_int (response_timeout_cycles,                      UVM_ALL_ON | UVM_DEC)
      `uvm_field_enum(qch_ctrl_response_e, observed_response,       UVM_ALL_ON)
      `uvm_field_int (response_latency_cycles,                      UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "qch_controller_item");
      super.new(name);
      observed_response       = QCH_RSP_NONE;
      response_latency_cycles = 0;
    endfunction

  endclass

  // -------------------------------------------------------------------------
  // qch_device_response_item : QREQn 하강 이벤트 1회에 대한 반응 정책
  //
  // 다른 아이템과 소비 방식이 다르다. 이 아이템은 즉시 신호를 구동하지 않고,
  // driver 가 "다음 QREQn 하강 엣지"를 기다렸다가 정책을 적용하는 reactive
  // 아이템이다.
  //
  // DENY 를 다시 푸는 동작(Q_DENIED -> Q_CONTINUE -> Q_RUN)은 이 아이템의
  // 정책 대상이 아니다. controller 가 QREQn 을 HIGH 로 되돌려야만 가능하므로
  // driver 가 그 이벤트에 자동으로 반응해 QDENY 를 내린다.
  // -------------------------------------------------------------------------
  class qch_device_response_item extends qch_base_item;

    rand qch_device_policy_e policy;

    // QREQn 하강을 감지한 뒤 응답 엣지를 구동하기까지의 대기 사이클.
    // ACCEPT 이면 QACCEPTn 을 LOW 로, DENY 이면 QDENY 를 HIGH 로 내보내기까지의
    // 시간이며, 양쪽 정책에 동일하게 적용된다.
    //
    // IHI0068D 는 디바이스의 응답 시간에 상한을 두지 않는다. 실제 디바이스도
    // 지금 조용해져도 되는지 판단하는 데 시간이 걸리므로 거부 역시 즉시
    // 일어나지 않는다. 따라서 이 지연을 DENY 경로에서 0 으로 묶지 않는다.
    rand int unsigned response_delay_cycles;

    constraint c_response_delay { soft response_delay_cycles inside {[0:20]}; }

    `uvm_object_utils_begin(qch_device_response_item)
      `uvm_field_enum(qch_device_policy_e, policy,                UVM_ALL_ON)
      `uvm_field_int (response_delay_cycles,                      UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "qch_device_response_item");
      super.new(name);
    endfunction

  endclass

  // -------------------------------------------------------------------------
  // qch_device_active_item : QACTIVE 토글 1회 (primitive)
  //
  // IHI0068D 2.1.1: "transitions on QACTIVE are not restricted by the values
  // on QREQn or on the QACCEPTn and QDENY output pair."
  // 따라서 handshake 상태와 무관하게 아무 때나 발행 가능하다.
  // -------------------------------------------------------------------------
  class qch_device_active_item extends qch_base_item;

    rand qch_active_action_e action;

    `uvm_object_utils_begin(qch_device_active_item)
      `uvm_field_enum(qch_active_action_e, action, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "qch_device_active_item");
      super.new(name);
    endfunction

  endclass

  // -------------------------------------------------------------------------
  // qch_monitor_item : monitor 가 관측한 상태 전이 1회
  //
  // 자극 아이템과 형태가 다르다. 자극 아이템은 "무엇을 하려 했는가"를 담고
  // 이 아이템은 "무엇이 일어났는가"를 담는다. 커버리지는 후자에서 나와야 한다.
  // VIP 가 PASSIVE 역할일 때는 자극 아이템이 아예 생성되지 않으므로, 커버리지가
  // 자극 아이템에 의존하면 그 구성에서 전부 비게 된다.
  //
  // 모든 필드는 monitor 가 채우므로 rand 가 아니다.
  // -------------------------------------------------------------------------
  class qch_monitor_item extends uvm_sequence_item;

    qch_state_e  prev_state;
    qch_state_e  state;
    bit          qactive;         // 전이 시점의 QACTIVE 값
    int unsigned cycles_in_prev;  // 직전 상태에 머문 사이클 수

    `uvm_object_utils_begin(qch_monitor_item)
      `uvm_field_enum(qch_state_e, prev_state, UVM_ALL_ON)
      `uvm_field_enum(qch_state_e, state,      UVM_ALL_ON)
      `uvm_field_int (qactive,                 UVM_ALL_ON | UVM_BIN)
      `uvm_field_int (cycles_in_prev,          UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "qch_monitor_item");
      super.new(name);
    endfunction

  endclass

endpackage
