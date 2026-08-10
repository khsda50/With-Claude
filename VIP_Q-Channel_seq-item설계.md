# Q-Channel Responder Agent — seq_item 설계 검토

작성 목적: CRMU/PMU 검증용 UVM agent를 만들기 위한 **seq_item 후보 비교와 결정 근거 기록**.
결정마다 "왜 그렇게 했고, 다른 선택지는 무엇이었고, 왜 버렸는지"를 남긴다 — 이 문서 자체가 면접 답변의 원본이 된다.

> ⚠️ 상태 이름·인코딩·신호 극성은 기억 기반 정리다. **착수 전 AMBA Low Power Interface 스펙 문서로 대조 필수.**

---

## 0. 전제

| 항목 | 결정 |
|---|---|
| DUT | CRMU/PMU (= Q-Channel의 **controller** 측) |
| Agent | **Device 측 responder** — DUT가 먼저 요청하고 agent가 응답 |
| Agent가 구동 | QACCEPTn, QDENY, QACTIVE |
| Agent가 관찰 | QREQn |
| 인스턴스 | 도메인 수만큼 N개 (config로 개별 제어) |

responder를 고른 이유: 검증 대상이 controller이므로 상대편이 필요하다. 부수 효과로
(1) DUT가 대화를 시작하는 반응형 구조라 initiator보다 설계 난도가 높고,
(2) 도메인마다 인스턴스를 복제하므로 config·파라미터화 설계가 필요해진다.

---

## 1. Q-Channel 상태 (참조)

인코딩 `{QREQn, QACCEPTn, QDENY}`. QREQn·QACCEPTn은 active-low.

| 상태 | QREQn | QACCEPTn | QDENY | 인코딩 | 다음 전이를 만드는 쪽 |
|---|:---:|:---:|:---:|:---:|---|
| Q_RUN | 1 | 1 | 0 | 3'b110 | controller (요청) |
| Q_REQUEST | 0 | 1 | 0 | 3'b010 | **device (응답)** |
| Q_STOPPED | 0 | 0 | 0 | 3'b000 | controller (해제) |
| Q_EXIT | 1 | 0 | 0 | 3'b100 | **device (복귀)** |
| Q_DENIED | 0 | 1 | 1 | 3'b011 | controller (해제) |
| Q_CONTINUE | 1 | 1 | 1 | 3'b111 | **device (복귀)** |

```
수락 경로:  Q_RUN → Q_REQUEST → Q_STOPPED → Q_EXIT     → Q_RUN
거절 경로:  Q_RUN → Q_REQUEST → Q_DENIED  → Q_CONTINUE → Q_RUN
```

불법 조합: `3'b001` {0,0,1}, `3'b101` {1,0,1} → **assertion 대상** (coverage 아님)

프로토콜 규칙 — item 설계를 제약하는 것들:
1. device는 응답(accept/deny) 후 controller가 QREQn을 해제할 때까지 **번복 불가**
2. controller는 Q_RUN 복귀 전 **재요청 불가**
3. **QACTIVE는 이 FSM에 속하지 않는다** — device가 활동 필요를 알리는 독립 신호

---

## 2. 공통 타입

```systemverilog
typedef enum bit [2:0] {
  Q_RUN      = 3'b110,   // {QREQn, QACCEPTn, QDENY}
  Q_REQUEST  = 3'b010,
  Q_STOPPED  = 3'b000,
  Q_EXIT     = 3'b100,
  Q_DENIED   = 3'b011,
  Q_CONTINUE = 3'b111
} qch_state_e;

typedef enum bit { QCH_ACCEPT, QCH_DENY } qch_resp_e;
```

---

## 3. 후보 A — 신호 이벤트 단위

**발상**: 1 item = 신호 하나를 한 번 구동.

```systemverilog
typedef enum { QCH_SIG_QACCEPTN, QCH_SIG_QDENY, QCH_SIG_QACTIVE } qch_sig_e;

class qch_evt_item extends uvm_sequence_item;

  rand qch_sig_e     sig;     // 구동할 신호
  rand bit           value;   // 구동할 값
  rand int unsigned  delay;   // 지금부터 대기할 사이클

  constraint c_delay { delay inside {[0:15]}; }

  `uvm_object_utils_begin(qch_evt_item)
    `uvm_field_enum(qch_sig_e, sig,  UVM_ALL_ON)
    `uvm_field_int (value,           UVM_ALL_ON)
    `uvm_field_int (delay,           UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "qch_evt_item");
    super.new(name);
  endfunction

endclass
```

**표현 가능**: 신호 하나를 언제 어떤 값으로 구동할지.

**표현 불가**:
- "요청이 들어왔다"는 개념 자체가 없다 → 시퀀스가 인터페이스를 직접 폴링해야 QREQn을 안다
- 규칙 1·2를 driver가 지킬 수 없다. 시퀀스가 잘못 짜면 번복·불법 조합이 그대로 나간다
- "수락했다"는 사건이 없다 → **coverage로 쓸 어휘가 없다**. `sig`/`value`/`delay`를 커버해봐야 의미가 없다

**판정: 기각.** 프로토콜 지식이 driver가 아니라 시퀀스로 새어 나간다. VIP가 아니라 핀 위글러.

---

## 4. 후보 B — 응답 정책 단위 ★ (drive item)

**발상**: 1 item = "다음에 들어올 요청 하나에 이렇게 답하라".

### 4.1 공통 베이스

QACTIVE를 별도 item으로 분리하되 **같은 sequencer**로 흘리기 위한 타입 통일용.

```systemverilog
// 순수 타입 통일 목적. 억지 공통 필드를 두지 않는다.
virtual class qch_item_base extends uvm_sequence_item;
  function new(string name = "qch_item_base");
    super.new(name);
  endfunction
endclass
```

> 공통 필드가 없는 베이스를 두는 이유: `uvm_sequencer #(qch_item_base)` 하나로
> 응답 정책과 QACTIVE 제어를 **하나의 시간축에 섞어 보내기 위해서**다.
> 두 sequencer로 나누면 "QACTIVE가 떠 있는 동안 들어온 요청"을 시퀀스가 의도적으로 만들 수 없다.
> 공통점이 없는데 공통 필드를 발명하지 않는 것도 결정이다.

### 4.2 응답 정책 item

```systemverilog
class qch_resp_item extends qch_item_base;

  // ---- 자극 (rand) ----
  rand qch_resp_e    response;       // 이번 요청에 수락/거절
  rand int unsigned  resp_latency;   // QREQn assert 감지 → 응답 구동까지
  rand int unsigned  exit_latency;   // QREQn deassert 감지 → 복귀까지

  // ---- 결과 (driver가 채움, non-rand) ----
  time               req_detected;   // QREQn 감지 시각
  time               resp_driven;    // 응답 구동 시각
  bit                qactive_at_req; // 요청 감지 시점의 QACTIVE 값
  bit                aborted;        // 요청을 못 받고 종료

  constraint c_resp_latency { resp_latency inside {[0:31]}; }
  constraint c_exit_latency { exit_latency inside {[0:15]}; }
  constraint c_resp_dist    { response dist { QCH_ACCEPT := 8,
                                              QCH_DENY   := 2 }; }

  `uvm_object_utils_begin(qch_resp_item)
    `uvm_field_enum(qch_resp_e, response,     UVM_ALL_ON)
    `uvm_field_int (resp_latency,             UVM_ALL_ON)
    `uvm_field_int (exit_latency,             UVM_ALL_ON)
    `uvm_field_int (qactive_at_req,           UVM_ALL_ON | UVM_NOCOMPARE)
  `uvm_object_utils_end

  function new(string name = "qch_resp_item");
    super.new(name);
  endfunction

endclass
```

### 4.3 QACTIVE 제어 item

```systemverilog
class qch_active_item extends qch_item_base;

  rand bit           level;   // QACTIVE 구동 값
  rand int unsigned  delay;   // 발행 전 대기 사이클
  rand int unsigned  hold;    // level=1 유지 사이클 (0 = 다음 item까지 유지)

  constraint c_delay { delay inside {[0:63]}; }
  constraint c_hold  { hold  inside {[0:63]}; }

  `uvm_object_utils_begin(qch_active_item)
    `uvm_field_int(level, UVM_ALL_ON)
    `uvm_field_int(delay, UVM_ALL_ON)
    `uvm_field_int(hold,  UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "qch_active_item");
    super.new(name);
  endfunction

endclass
```

### 4.4 driver가 어떻게 생기는가 (프로토콜 규칙이 갇히는 자리)

```
forever begin
  seq_item_port.get_next_item(base_item);

  if ($cast(resp_item, base_item)) begin
    wait (vif.QREQn === 1'b0);              // 요청 대기
    resp_item.req_detected   = $time;
    resp_item.qactive_at_req = vif.QACTIVE;

    repeat (resp_item.resp_latency) @(posedge clk);

    if (resp_item.response == QCH_ACCEPT) vif.QACCEPTn <= 1'b0;
    else                                  vif.QDENY    <= 1'b1;
    resp_item.resp_driven = $time;

    wait (vif.QREQn === 1'b1);              // 규칙 1: 해제 전까지 번복 금지
    repeat (resp_item.exit_latency) @(posedge clk);

    vif.QACCEPTn <= 1'b1;                   // Q_RUN 복귀
    vif.QDENY    <= 1'b0;
  end
  else if ($cast(act_item, base_item)) begin
    repeat (act_item.delay) @(posedge clk);
    vif.QACTIVE <= act_item.level;
    if (act_item.level && act_item.hold > 0) begin
      repeat (act_item.hold) @(posedge clk);
      vif.QACTIVE <= 1'b0;
    end
  end

  seq_item_port.item_done();
end
```

규칙 1·2가 전부 driver 안에 있다. 시퀀스는 프로토콜을 몰라도 된다.

**장점**
- 필드가 전부 **도메인 언어** — "수락할지", "얼마나 뜸 들일지". 핀 이름이 하나도 없다
- 테스트가 의도만 말한다: `resp_item.response == QCH_DENY` 하나로 "이번엔 거절"
- coverage 어휘가 그대로 나온다 (§7)
- QACTIVE가 별도 item이라 **handshake와 무관한 시점의 wakeup**을 표현할 수 있다

**단점**
- item 하나의 수명이 길다(요청~복귀 전체). 그 사이 다른 item이 대기한다
  → QACTIVE를 다른 타입으로 뺀 것이 이 단점의 완충재. 응답 대기 중에도 QACTIVE는 못 건드리지만,
    필요하면 driver를 두 프로세스로 쪼개는 확장이 가능하다 (v2 과제)

**판정: 채택 (drive용).**

---

## 5. 후보 C — 완결 트랜잭션 단위 (monitor item)

**발상**: 1 item = 관찰된 handshake 한 사이클의 완전한 기록.

```systemverilog
class qch_xact_item extends uvm_sequence_item;

  // 전부 관찰값 — rand 없음
  qch_resp_e     response;         // 실제 응답
  bit            qactive_at_req;   // 요청 시점 QACTIVE
  bit            qactive_during;   // 사이클 도중 QACTIVE 상승 발생
  int unsigned   resp_latency;     // 요청 → 응답 사이클
  int unsigned   stopped_cycles;   // 정지/거절 유지 사이클
  int unsigned   exit_latency;     // 해제 → 복귀 사이클
  int unsigned   total_cycles;     // 전체
  int unsigned   idle_before;      // 직전 사이클 종료 → 이번 요청까지 (back-to-back 판별)

  time           t_req, t_resp, t_release, t_run;

  qch_state_e    state_trace[$];   // 방문 상태 순서
  bit            protocol_error;
  string         error_msg;

  `uvm_object_utils_begin(qch_xact_item)
    `uvm_field_enum (qch_resp_e, response,  UVM_ALL_ON)
    `uvm_field_int  (qactive_at_req,        UVM_ALL_ON)
    `uvm_field_int  (qactive_during,        UVM_ALL_ON)
    `uvm_field_int  (resp_latency,          UVM_ALL_ON)
    `uvm_field_int  (stopped_cycles,        UVM_ALL_ON)
    `uvm_field_int  (exit_latency,          UVM_ALL_ON)
    `uvm_field_int  (idle_before,           UVM_ALL_ON)
    `uvm_field_queue_enum(qch_state_e, state_trace, UVM_ALL_ON)
    `uvm_field_int  (protocol_error,        UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "qch_xact_item");
    super.new(name);
  endfunction

endclass
```

**왜 B와 합치지 않는가** — 이게 이 문서의 핵심 판단 중 하나다.

responder에서 **요청 시각과 요청 간격은 DUT가 정하는 값**이다. randomize 대상이 아니다.
이걸 B에 합치면 같은 클래스 안에 "내가 정하는 필드(rand)"와 "DUT가 정하는 필드(non-rand)"가
섞여서, 필드를 볼 때마다 어느 쪽인지 헷갈린다. constraint를 걸면 안 되는 필드에 실수로 걸게 된다.

→ **drive item과 monitor item을 분리한다.** scoreboard와 coverage는 monitor item(C)에서만 sampling.

**판정: 채택 (monitor용). B와 별도 클래스.**

---

## 6. 후보 D — 시나리오 단위

**발상**: 1 item = 이 도메인을 재우고 깨우는 전체 시나리오.

```systemverilog
typedef enum { POL_ALWAYS_ACCEPT, POL_DENY_FIRST_N, POL_RANDOM } qch_policy_e;

class qch_scenario_item extends uvm_sequence_item;

  rand qch_policy_e   policy;
  rand int unsigned   n_requests;
  rand qch_resp_e     responses[];      // 요청별 응답
  rand int unsigned   latencies[];      // 요청별 지연
  rand bit            wakeup_enable;
  rand int unsigned   wakeup_at_request; // 몇 번째 요청 중 wakeup
  rand int unsigned   deny_count;

  constraint c_size {
    responses.size() == n_requests;
    latencies.size() == n_requests;
    n_requests inside {[1:16]};
  }
  // ... policy에 따른 responses 결정 constraint가 계속 붙는다

endclass
```

**문제**
- 배열 필드 = 이 클래스는 **트랜잭션이 아니라 트랜잭션의 컨테이너**다. 이건 sequence의 일이다
- 사용자마다 원하는 시나리오가 달라서 `policy` enum과 필드가 **무한히 자란다**.
  누군가 "3번째 요청에서만 늦게 거절"을 원하면 필드가 또 추가된다 → 재사용성 붕괴
- coverage sampling 단위가 모호하다. item 하나가 요청 16번을 담고 있으면 "한 번 샘플"이 무엇인가?
- 되돌리기 비용이 최대. 모든 시퀀스가 이 거대 클래스에 의존한다

**판정: 기각.** 여기 있는 내용은 전부 **sequence 층**에 있어야 한다.
`qch_deny_first_n_seq`, `qch_wakeup_during_stop_seq` 같은 시퀀스로 표현하면
B의 item 조합만으로 전부 만들 수 있고, 새 시나리오는 새 클래스를 추가하면 된다.

---

## 7. 비교 요약

| | A 신호 이벤트 | **B 응답 정책** | **C 완결 트랜잭션** | D 시나리오 |
|---|---|---|---|---|
| 추상화 층위 | 핀 | **의도** | **관찰 기록** | 시나리오 |
| 프로토콜 규칙 위치 | 시퀀스 (누수) | **driver** | — (관찰만) | driver |
| 필드가 도메인 언어인가 | ✗ 핀 이름 | **✓** | **✓** | △ |
| randomize 의미 | 무의미 | **의미 있음** | 해당 없음 | 과도 |
| coverage 어휘 제공 | ✗ | △ (자극 측) | **✓ (주 소스)** | ✗ 모호 |
| 재사용성 | 낮음 | **높음** | **높음** | 매우 낮음 |
| 용도 | — | **drive** | **monitor** | — |

**결론: B(+`qch_active_item`) = drive / C = monitor.** A·D 기각.

---

## 8. 이 결정에서 따라 나오는 coverage

전부 **C(monitor item)** 에서 sampling.

```systemverilog
covergroup cg_qch @(sample_event);

  cp_response : coverpoint item.response;

  cp_state : coverpoint cur_state {
    bins run = {Q_RUN}; bins req = {Q_REQUEST}; bins stop = {Q_STOPPED};
    bins exitt = {Q_EXIT}; bins deny = {Q_DENIED}; bins cont = {Q_CONTINUE};
  }

  cp_trans : coverpoint cur_state {
    bins t_run_req   = (Q_RUN     => Q_REQUEST);
    bins t_req_stop  = (Q_REQUEST => Q_STOPPED);
    bins t_req_deny  = (Q_REQUEST => Q_DENIED);
    bins t_stop_exit = (Q_STOPPED => Q_EXIT);
    bins t_exit_run  = (Q_EXIT    => Q_RUN);
    bins t_deny_cont = (Q_DENIED  => Q_CONTINUE);
    bins t_cont_run  = (Q_CONTINUE=> Q_RUN);
  }

  cp_resp_latency : coverpoint item.resp_latency {
    bins immediate = {0};
    bins one       = {1};
    bins short     = {[2:7]};
    bins long      = {[8:31]};
  }

  cp_qactive_at_req : coverpoint item.qactive_at_req;
  cp_qactive_during : coverpoint item.qactive_during;

  cp_idle : coverpoint item.idle_before {
    bins back_to_back = {0};
    bins immediate    = {[1:3]};
    bins spaced       = {[4:$]};
  }

  // --- cross: 진짜 버그가 사는 자리 ---
  x_resp_lat    : cross cp_response, cp_resp_latency;
  x_resp_active : cross cp_response, cp_qactive_at_req;
  x_resp_wake   : cross cp_response, cp_qactive_during;

endgroup
```

**`x_resp_active` / `x_resp_wake`가 이 설계의 증거다.**
후보 B에 QACTIVE를 필드로 넣었다면(§4.1의 기각 선택지) QACTIVE 발생 시점이 handshake에
종속되어 이 cross를 못 만든다. **item이 표현하지 못하는 현상은 검증이 볼 수 없다** —
seq_item 설계가 곧 coverage 어휘 설계라는 것의 실물 증거.

불법 조합 `3'b001`, `3'b101`과 규칙 1(번복 금지)·규칙 2(재요청 금지)는 coverage가 아니라
**SVA assertion**으로 간다.

---

## 9. 결정 근거 요약 (면접용)

1. **agent 방향** — DUT가 controller이므로 device 측 responder. 반응형 구조 + 도메인별 다중 인스턴스.
2. **입도** — 핸드셰이크 한 사이클을 1 item으로. 그보다 낮으면 프로토콜 지식이 시퀀스로 새고,
   높으면 시나리오가 되어 재사용이 죽는다. 기준은 **"테스트에게 의미 있는 가장 작은 단위이면서,
   driver가 외부 문맥 없이 실행 가능할 만큼 완결된 것."**
3. **drive/monitor 분리** — responder에서는 요청 시각·간격이 DUT 소유라 rand가 아니다.
   자극 필드와 관찰 필드를 한 클래스에 섞지 않는다.
4. **QACTIVE 분리** — FSM과 시간축이 독립인 신호를 handshake item의 필드로 넣으면
   "요청과 무관한 wakeup"을 표현할 수 없고 cross coverage가 사라진다.
   별도 item 타입 + **같은 sequencer**로 두어 두 신호의 상관관계를 시퀀스가 만들 수 있게 했다.
5. **공통 베이스에 억지 필드를 두지 않았다** — 타입 통일이 목적이면 그것만 한다.

---

## 10. 다음 단계

- [ ] AMBA LPI 스펙으로 §1 대조 및 수정
- [ ] DUT 스펙 확정 — 도메인 2~3개 + 레지스터 인터페이스를 갖는 최소 CRMU
- [ ] 스펙 문서 **동결** → 이후 검증계획·coverage는 이 문서만 근거로 도출
- [ ] agent 구현 (item → driver → monitor → agent → env)
- [ ] SVA: 불법 조합 2개, 번복 금지, 재요청 금지
- [ ] coverage model 구현 → 랜덤 회귀 → hole 분석 → directed sequence 추가 → closure
- [ ] hole 중 unreachable 판정과 waiver 근거 기록 ← 면접 단골 질문
