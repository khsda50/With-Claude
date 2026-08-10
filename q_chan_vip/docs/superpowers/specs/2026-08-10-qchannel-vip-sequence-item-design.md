# Q-Channel VIP — sequence_item 설계

## 배경

여러 IP에 흩어진 Q-Channel(AMBA Low Power Interface, IHI0068D) 쌍을 재사용 가능한
체커+bind+stimulus로 다루는 VIP를 만드는 프로젝트의 첫 증분. 이 문서는 그 중
**stimulus의 최소 단위인 sequence_item**만을 범위로 한다. driver/monitor/agent/
SVA 체커/bind는 별도 증분(추후 spec)에서 다룬다.

## 프로토콜 근거

IHI0068D §2.1 Q-Channel interface specification 기준.

- 신호: `QREQn`(Controller→Device), `QACCEPTn`/`QDENY`/`QACTIVE`(Device→Controller)
- 상태(Table 2-1): Q_RUN / Q_REQUEST / Q_STOPPED / Q_EXIT / Q_DENIED / Q_CONTINUE
- Handshake rules(§2.1.2)에서 확인한 핵심 제약:
  - `QDENY`는 `QREQn`이 HIGH로 돌아와야만 다시 LOW로 내려간다 — 즉 **deny를 푸는
    것은 Device 단독 결정이 아니라 Controller의 재요청을 반드시 거쳐야 한다.**
  - `QACTIVE`는 handshake와 독립이며 Device가 어떤 상태에서든 구동 가능하다
    (§2.1.1: "transitions on QACTIVE are not restricted by the values on QREQn
    or on the QACCEPTn and QDENY output pair").

이 두 사실이 아래 클래스 분리의 근거다.

## 범위

**포함**: `qch_base_item`과 3개의 role별 derived 아이템 클래스, 그 필드와 각
필드의 의미/제약.

**제외**: driver, monitor, sequencer, agent, config object, SVA 프로토콜 체커,
bind 파일, 실제 시퀀스(랜덤 트래픽 생성 로직). 이 아이템들은 미래 증분에서
이 클래스들을 소비하는 driver를 통해 실제로 신호를 구동한다.

### 다음 증분을 위한 메모: monitor 아이템에는 상태 필드가 필요하다

여기 정의하는 3개 아이템은 **자극(의도)** 표현용이다. 커버리지는 "무엇을
요청했는가"가 아니라 "실제로 무엇이 일어났는가"에서 나와야 하므로, monitor가
신호에서 복원하는 아이템은 이 3개와 필드 구성이 다르다. 특히:

- Q-Channel의 핵심 커버리지는 6개 상태(Q_RUN/Q_REQUEST/Q_STOPPED/Q_EXIT/
  Q_DENIED/Q_CONTINUE) 방문과 그 전이인데, 이는 아이템 하나("토글 1회")로
  표현되지 않는다. monitor가 상태를 복원해 `qch_state_e` 필드로 실어야
  covergroup에서 state/transition bin으로 잡을 수 있다.
- 이 VIP는 passive 모드(양쪽 다 실제 RTL을 관찰만)를 지원해야 하므로, 그때는
  driven 아이템이 존재하지 않는다. 커버리지가 driven 아이템에 의존하면 passive
  모드에서 전부 비게 된다.

따라서 monitor 아이템을 별도 클래스로 둘지, 기존 아이템에 상태 필드를 추가할지는
monitor 증분 설계 시점에 결정한다. 이번 증분에서는 결정하지 않는다.

한편 driven 아이템에 대한 covergroup도 별도로 의미가 있다 — "내 랜덤화가
accept_delay/policy 공간을 제대로 훑었는가"라는 **자극 품질** 측정이며, 위의
DUT 동작 커버리지와는 목적이 다르다.

## 클래스 구조

```
qch_base_item (uvm_sequence_item)
  ├── qch_controller_item      — QREQn 토글 1회 (primitive)
  ├── qch_device_response_item — QREQn 하강 이벤트 1회에 대한 반응 정책
  └── qch_device_active_item   — QACTIVE 토글 1회 (QREQn과 무관, primitive)
```

세 derived 클래스로 나눈 이유: Controller와 Device는 구동하는 신호와 의사결정
폭이 근본적으로 다르고(Controller는 QREQn 한 비트만, Device는 accept/deny 정책+
QACTIVE), Device 내에서도 "QREQn에 반응하는 것"과 "QREQn과 무관하게 자발적으로
QACTIVE를 구동하는 것"은 트리거 자체가 다르다(이벤트 반응형 vs 무조건 즉시
구동형). 하나의 클래스에 욱여넣으면 role/kind에 따라 무의미해지는 필드가
섞이고, 랜덤화 제약도 조건부로 지저분해진다.

## 필드 설계

### `qch_base_item`

```systemverilog
rand int unsigned pre_delay_cycles;
```

아이템을 실제로 구동하기 전 대기하는 사이클 수. 어느 클럭 기준인지는 driver/
config가 결정한다(이 아이템 자체는 클럭을 모른다).

### `qch_controller_item`

```systemverilog
typedef enum { REQUEST_QUIESCENCE, ALLOW_RUN } qch_req_action_e;
rand qch_req_action_e action;

typedef enum { RSP_NONE, RSP_ACCEPTED, RSP_DENIED, RSP_TIMEOUT } qch_ctrl_response_e;
qch_ctrl_response_e observed_response;      // 드라이버가 구동 후 채움. randomize 대상 아님
int unsigned         response_latency_cycles; // 위와 동일
rand int unsigned    response_timeout_cycles;
```

- `REQUEST_QUIESCENCE` = `QREQn` LOW 구동, `ALLOW_RUN` = `QREQn` HIGH 구동.
  "assert"라는 단어를 피한 이유: `QREQn`이 active-LOW라 "request를 assert한다"가
  "신호를 HIGH로 만든다"는 일반적 어감과 충돌해 헷갈리기 쉽다.
- `observed_response`/`response_latency_cycles`는 랜덤화 대상이 아니라 driver가
  실제 구동 후 채워 넣는 결과 필드다. 커버리지/디버그용이며, 프로토콜 위반
  여부 판정은 이 필드의 책임이 아니다(아래 "검사와의 경계" 참고).
- `response_timeout_cycles`는 스펙이 응답 시간 상한을 정의하지 않으므로,
  VIP가 "무한 대기"를 피하기 위해 두는 시험 편의상의 값이다. 이번 증분에는
  아직 agent config가 없으므로, 이 필드 자체에 합리적인 기본 범위(예:
  `inside {[10:1000]}`)를 soft constraint로 건다. 나중에 config object가
  생기면 그 기본값을 참조하도록 교체한다.

### `qch_device_response_item`

```systemverilog
typedef enum { QCH_ACCEPT, QCH_DENY } qch_device_policy_e;
rand qch_device_policy_e policy;
rand int unsigned response_delay_cycles;  // 두 정책 모두에 적용
```

`response_delay_cycles`는 `QREQn` 하강을 감지한 뒤 응답 엣지를 구동하기까지의
시간이다. ACCEPT면 `QACCEPTn`을 LOW로, DENY면 `QDENY`를 HIGH로 내보내기까지의
지연이며, **두 정책 모두에 동일하게 적용된다.**

DENY 경로의 지연을 0으로 묶지 않는 이유는 두 가지다.

1. IHI0068D는 디바이스의 응답 시간에 상한을 두지 않는다. 실제 디바이스도 지금
   조용해져도 되는지 판단하는 데 시간이 걸리므로 거부 역시 즉시 일어나지 않는다.
   0으로 묶으면 "느린 거부"에서만 드러나는 문제를 영원히 못 잡는다.
2. `(policy == QCH_DENY) -> response_delay_cycles == 0` 같은 implication 제약을
   걸면 랜덤 분포가 무너진다. SystemVerilog는 해공간 전체에 균등 분포하므로,
   ACCEPT는 지연 21가지 × 1 = 21개 조합, DENY는 1개 조합이 되어 DENY가 약 4.5%
   확률로만 나온다. deny 핸드셰이크는 이 VIP의 존재 이유 절반인데 그것이
   22번에 1번만 생성된다.

이 아이템은 "다음 `QREQn` 하강 엣지 1회에 대해 어떻게 반응할지"를 미리 예약해
두는 성격이다. driver는 이 아이템을 받으면 즉시 신호를 구동하지 않고, 다음
`QREQn` 하강을 기다렸다가 정책을 적용한다 — 다른 두 클래스(즉시 구동형)와
소비 방식이 다르다는 점을 명시한다.

`DENY`를 다시 푸는 동작(Q_DENIED → Q_CONTINUE → Q_RUN)은 이 아이템의 정책
대상이 아니다. Handshake rules상 Controller가 `QREQn`을 HIGH로 되돌려야만
가능하므로, driver가 그 이벤트에 자동으로 반응해 `QDENY`를 내린다.

### `qch_device_active_item`

```systemverilog
typedef enum { ACTIVE_HIGH, ACTIVE_LOW } qch_active_action_e;
rand qch_active_action_e action;
```

`QREQn`/`QACCEPTn`/`QDENY`와 완전히 독립적으로 아무 때나 발행 가능하다.

## 검사와의 경계

이 아이템들은 순수하게 자극 생성용이다. "deny 이후 controller가 반드시
`QREQn`을 deassert해야 한다" 같은 프로토콜 합법성은 여기서 강제하지 않는다 —
의도적으로 위반하는 시퀀스도 만들 수 있게 열어두고, 그 위반을 잡는 것은 별도
증분의 재사용 SVA 체커(bind) 몫이다.

## 파일 구성

`uvm/qch_items.sv` 한 파일에 `package qch_item_pkg` 로 감싸서 4개 클래스를
모두 담는다. 서로 강하게 결합되어 있고(base+derived), 각 클래스가 작아
분리하면 오히려 탐색 비용만 늘어난다.

## 테스트/검증 상태

이 환경에는 SystemVerilog 시뮬레이터가 없어 컴파일 검증은 불가능하다.
`uvm/simple_test.sv` 수준의 단순 UVM 문법을 따르며, 실제 컴파일은 시뮬레이터가
있는 환경에서 확인이 필요하다.
