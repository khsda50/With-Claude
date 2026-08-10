# Q-Channel VIP — driver / monitor / agent 설계

## 배경

AMBA Low Power Interface(IHI0068D) Q-Channel VIP의 두 번째 증분. 첫 증분에서
sequence_item 4개 클래스를 만들었고(`uvm/qch_items.sv`, 커밋 `4bd80c2`), 이번에는
그 아이템을 실제 신호로 바꾸는 driver와, 신호를 관찰해 상태를 복원하는 monitor,
그리고 이들을 묶는 agent를 만든다.

SVA 프로토콜 체커와 bind 파일은 여전히 이번 증분 범위 밖이다.

## 확정된 요구사항

- **VIP는 Controller 역할과 Device 역할을 모두 구동할 수 있어야 한다.** 인스턴스마다
  config로 고른다. 여러 IP에 흩어진 Q-Channel 쌍을 같은 VIP로 다루기 위해서다.
- Device 역할일 때, `QREQn` 하강에 대한 응답은 **responder 시퀀스가 계속 돌면서
  자동 생성**한다. 특정 시나리오가 필요한 테스트는 이 시퀀스를 자기 것으로 교체한다.

## 범위

**포함**: 인터페이스, config object, monitor 아이템(상태 표현), monitor,
controller driver, device driver, sequencer 3종, responder 시퀀스, agent.

**제외**: SVA 프로토콜 체커, bind 파일, 스코어보드, 커버리지 모델, P-Channel.

## 파일 구성

```
uvm/qch_if.sv              인터페이스 (신호 + modport)
uvm/qch_items.sv           [기존 확장] qch_state_e + qch_monitor_item 추가
uvm/qch_agent_pkg.sv       아래 .svh 들을 include 하는 패키지
  qch_config.svh           역할/타이밍 설정
  qch_monitor.svh          신호 -> 상태 복원, analysis port 발행
  qch_sequencers.svh       controller / device-response / device-active sequencer
  qch_controller_driver.svh
  qch_device_driver.svh
  qch_responder_seq.svh
  qch_agent.svh
```

클래스를 파일별로 쪼개고 패키지가 `include`하는 구성으로 간다. 한 파일에 다 넣으면
driver 두 개와 moniter가 섞여 읽기 어려워지고, 나중에 P-Channel VIP를 만들 때
비슷한 구조를 복사하기도 나쁘다.

## 설계

### 1. 인터페이스 (`qch_if.sv`)

Q-Channel 4개 신호 + 클럭 + 리셋을 담는다.

```systemverilog
interface qch_if (input logic clk, input logic rst_n);
  logic QREQn;
  logic QACCEPTn;
  logic QDENY;
  logic QACTIVE;

  modport controller (output QREQn, input QACCEPTn, input QDENY, input QACTIVE,
                      input clk, input rst_n);
  modport device     (input QREQn, output QACCEPTn, output QDENY, output QACTIVE,
                      input clk, input rst_n);
  modport monitor    (input QREQn, input QACCEPTn, input QDENY, input QACTIVE,
                      input clk, input rst_n);
endinterface
```

modport로 신호 소유권을 강제한다. Controller가 실수로 `QACCEPTn`을 구동하는 것 같은
실수를 컴파일 단계에서 잡기 위해서다.

`QDENY`와 `QACTIVE`는 IHI0068D §2.1.4가 생략을 허용한다(각각 controller에서 LOW로
tie). 이번 증분은 **4개 신호가 모두 존재한다고 가정**하고, 생략된 인터페이스 지원은
필요해지면 별도로 다룬다.

### 2. 상태 표현 (`qch_items.sv`에 추가)

IHI0068D Table 2-1의 6개 상태에 illegal 조합을 더한다.

```systemverilog
typedef enum bit [2:0] {
  QCH_ST_RUN,       // QREQn=1, QACCEPTn=1, QDENY=0
  QCH_ST_REQUEST,   // QREQn=0, QACCEPTn=1, QDENY=0
  QCH_ST_STOPPED,   // QREQn=0, QACCEPTn=0, QDENY=0
  QCH_ST_EXIT,      // QREQn=1, QACCEPTn=0, QDENY=0
  QCH_ST_DENIED,    // QREQn=0, QACCEPTn=1, QDENY=1
  QCH_ST_CONTINUE,  // QREQn=1, QACCEPTn=1, QDENY=1
  QCH_ST_ILLEGAL    // QACCEPTn=0, QDENY=1 (Table 2-1 "Unused")
} qch_state_e;
```

monitor가 발행하는 아이템은 자극 아이템과 형태가 달라서 별도 클래스로 둔다.

```systemverilog
class qch_monitor_item extends uvm_sequence_item;
  qch_state_e  prev_state;
  qch_state_e  state;
  bit          qactive;          // 전이 시점의 QACTIVE 값
  int unsigned cycles_in_prev;   // 직전 상태에 머문 사이클 수
endclass
```

**자극 아이템을 재사용하지 않는 이유**: 자극 아이템은 "무엇을 하려 했는가"를 담고,
이 아이템은 "무엇이 일어났는가"를 담는다. 커버리지는 후자에서 나와야 한다. VIP가
PASSIVE 역할일 때는 자극 아이템이 아예 생성되지 않으므로, 커버리지가 자극 아이템에
의존하면 그 구성에서 전부 비게 된다.

`cycles_in_prev`를 넣는 이유는 상태 방문뿐 아니라 **체류 시간**이 검증 대상이기
때문이다. `Q_EXIT`이 항상 1사이클이면 그 구간의 문제를 못 잡는다.

이 아이템의 필드는 monitor가 채우므로 `rand`가 아니다.

### 3. Config object (`qch_config.svh`)

```systemverilog
typedef enum bit [1:0] {
  QCH_ROLE_CONTROLLER,
  QCH_ROLE_DEVICE,
  QCH_ROLE_PASSIVE
} qch_role_e;

class qch_config extends uvm_object;
  qch_role_e   role                  = QCH_ROLE_PASSIVE;
  bit          start_responder_seq   = 1;      // DEVICE 역할일 때만 의미 있음
  bit          reset_qreqn_high      = 1;      // CONTROLLER 역할일 때만 의미 있음
  int unsigned exit_delay_cycles     = 0;      // DEVICE 역할일 때만 의미 있음
endclass
```

- `role` 기본값을 `PASSIVE`로 두는 이유: 설정을 깜빡했을 때 아무 신호도 구동하지
  않는 쪽이 안전하다. 실수로 DUT 신호와 충돌하는 것보다 낫다.
- `reset_qreqn_high` — IHI0068D §2.1.2 "Device reset"은 controller가 리셋 해제
  시점에 `QREQn` LOW(`Q_STOPPED`) 또는 HIGH(`Q_EXIT`) 중 하나를 고르도록 허용한다.
  둘 다 합법이므로 config로 노출한다.
- `exit_delay_cycles` — 아래 4절 참조.

### 4. Device driver (`qch_device_driver.svh`)

구동 신호: `QACCEPTn`, `QDENY`, `QACTIVE`.

**리셋 동작 (스펙 요구사항)**. IHI0068D §2.1.2:
> At reset assertion, a device must drive both QACCEPTn and QDENY LOW.

따라서 `rst_n`이 LOW인 동안 `QACCEPTn=0`, `QDENY=0`을 구동한다. `QACTIVE`는 스펙이
LOW/HIGH 둘 다 허용하므로 LOW로 리셋한다(§2.1.2가 시작 시 할 일이 없으면 LOW를 권장).

**응답 루프**:

```
반복 {
  seq_item_port.get_next_item(req)      // QREQn 하강 전에 미리 확보
  QREQn 하강 엣지 대기
  req.response_delay_cycles 만큼 대기
  req.policy 가 QCH_ACCEPT 이면 QACCEPTn <= 0
                QCH_DENY   이면 QDENY    <= 1
  seq_item_port.item_done()
}
```

아이템을 엣지 **전에** 확보하는 이유: 엣지가 온 뒤에 시퀀스를 기다리면 응답이
그만큼 늦어져 `response_delay_cycles`가 의미를 잃는다.

**되돌리는 엣지는 자동 처리한다.** `QREQn`이 다시 HIGH가 되면:
- `Q_EXIT`(`QACCEPTn=0`) 상태였으면 `exit_delay_cycles` 후 `QACCEPTn <= 1`
- `Q_CONTINUE`(`QDENY=1`) 상태였으면 `exit_delay_cycles` 후 `QDENY <= 0`

이 두 엣지는 아이템 정책의 대상이 아니다. IHI0068D handshake rules상 device에게
선택지가 없고(그 상태에서 할 수 있는 전이가 하나뿐), controller가 `QREQn`을 올린
뒤에만 가능하기 때문이다. 따라서 **타이밍만** config `exit_delay_cycles`로 준다.

> 첫 증분 최종 리뷰에서 "깨어날 때 지연을 아이템별로 랜덤화할 수 없다"는 지적이
> 있었고 다음 증분으로 미뤘다. 이번에는 config 고정값으로 최소한만 해결한다.
> 매 전이마다 다른 지연이 필요해지면 그때 아이템 필드로 올린다.

**`QACTIVE`는 sequencer부터 분리한다.** `qch_device_active_item`은 handshake와 무관하게
아무 때나 올 수 있다(§2.1.1). 그런데 위 응답 루프는 `QREQn` 하강을 기다리며 오래
블록될 수 있으므로, **두 종류 아이템이 같은 sequencer를 공유하면 응답을 기다리는 동안
`QACTIVE` 아이템이 막힌다.** "아무 때나 구동 가능"이라는 스펙 성질이 깨진다.

따라서 DEVICE 역할 agent는 **sequencer를 두 개** 만든다.

```
qch_device_response_sequencer  --> driver.rsp_seq_item_port  (응답 프로세스)
qch_device_active_sequencer    --> driver.act_seq_item_port  (QACTIVE 프로세스)
```

driver는 `uvm_seq_item_pull_port`를 두 개 갖고, `run_phase`에서 두 프로세스를 `fork`로
독립 실행한다. 서로 블록되지 않고, 아이템 타입을 `$cast`으로 갈라낼 필요도 없다.

**`pre_delay_cycles` 취급**: `qch_device_response_item`에서는 **무시한다**.
이 아이템은 즉시 구동형이 아니라 `QREQn` 하강을 기다리는 반응형이라, "구동 전 대기"의
기준점이 없다. 지연은 `response_delay_cycles` 하나만 쓴다. `qch_device_active_item`
에서는 정상적으로 사용한다(즉시 구동형이므로 기준점이 명확하다).

### 5. Controller driver (`qch_controller_driver.svh`)

구동 신호: `QREQn`.

**리셋 동작**: `rst_n` LOW 동안 `config.reset_qreqn_high` 값을 구동한다.

**구동 루프**:

```
반복 {
  seq_item_port.get_next_item(req)
  req.pre_delay_cycles 만큼 대기
  req.action 이 QCH_REQUEST_QUIESCENCE 이면 QREQn <= 0, ALLOW_RUN 이면 QREQn <= 1
  응답 대기 (아래)
  결과를 req 에 기록
  seq_item_port.item_done()
}
```

**응답 대기**는 `action`에 따라 다르다.

| action | 기다리는 것 | 기록되는 `observed_response` |
|---|---|---|
| `QCH_REQUEST_QUIESCENCE` | `QACCEPTn` 하강 또는 `QDENY` 상승 | `QCH_RSP_ACCEPTED` / `QCH_RSP_DENIED` |
| `QCH_ALLOW_RUN` | `Q_RUN` 도달 (`QACCEPTn=1`, `QDENY=0`) | `QCH_RSP_ACCEPTED` |

`response_timeout_cycles` 안에 아무 일도 없으면 `QCH_RSP_TIMEOUT`을 기록하고 루프를
계속한다. **timeout은 `uvm_error`를 내지 않는다** — 스펙이 응답 시간 상한을 정의하지
않으므로 timeout 자체는 프로토콜 위반이 아니고, 이 필드는 관측 기록일 뿐이다.
위반 판정은 SVA 몫이다.

`response_latency_cycles`에는 구동 시점부터 응답 관측까지의 사이클 수를 기록한다.

> `QCH_ALLOW_RUN`의 결과에 `QCH_RSP_ACCEPTED`를 재사용하는 것은 정확한 표현이
> 아니다. 첫 증분 리뷰에서 "`qch_ctrl_response_e`에 ALLOW_RUN 결과를 적을 칸이
> 없다"는 지적이 나왔고 다음 증분으로 미뤘다. 이번에도 enum을 넓히지 않고, 대신
> **`qch_controller_item.action`과 같이 봐야 의미가 확정된다**는 점을 문서화한다.
> enum을 넓히는 것은 소비자(커버리지/스코어보드)가 생길 때 함께 한다.

### 6. Responder 시퀀스 (`qch_responder_seq.svh`)

Device 역할일 때 `config.start_responder_seq`가 1이면 agent가 `run_phase`에서
자동으로 시작한다.

```
forever begin
  req = qch_device_response_item::type_id::create(...)
  start_item(req)
  req.randomize()
  finish_item(req)     // driver 가 item_done 할 때까지 블록됨
end
```

driver가 아이템을 하나 소비할 때마다 다음 것이 새로 randomize되므로, 매 요청마다
독립적으로 뽑힌 accept/deny가 적용된다. 첫 증분에서 고친 50:50 분포가 평상 테스트에서
실제로 살아나는 지점이 여기다.

특정 시나리오가 필요한 테스트는 `config.start_responder_seq = 0`으로 두고 자기
시퀀스를 직접 올린다.

### 7. Monitor (`qch_monitor.svh`)

역할과 무관하게 항상 만들어진다. 4개 신호를 매 클럭 샘플링해서:

1. `QREQn`/`QACCEPTn`/`QDENY` 조합을 `qch_state_e`로 매핑
2. 상태가 바뀌면 `qch_monitor_item`을 만들어 `prev_state`, `state`, `qactive`,
   `cycles_in_prev`를 채우고 analysis port로 발행
3. 상태가 그대로면 체류 카운터만 증가

**monitor는 어떤 위반도 보고하지 않는다.** `QCH_ST_ILLEGAL`에 진입해도 그 상태를
발행할 뿐 `uvm_error`를 내지 않는다. 프로토콜 검사는 SVA 증분이 담당하고, monitor가
같은 검사를 중복하면 이중 관리 대상이 된다.

리셋 중에는 상태 추적을 하지 않고, 리셋 해제 후 첫 샘플에서 현재 상태를 초기
상태로 잡는다.

### 8. Agent (`qch_agent.svh`)

`build_phase`에서 `config.role`을 보고 필요한 것만 만든다.

| role | monitor | sequencer | driver |
|---|---|---|---|
| `QCH_ROLE_CONTROLLER` | O | 1개 (controller) | controller driver |
| `QCH_ROLE_DEVICE` | O | **2개** (response, active) | device driver |
| `QCH_ROLE_PASSIVE` | O | X | X |

`run_phase`에서, 역할이 `DEVICE`이고 `start_responder_seq`가 1이면 responder 시퀀스를
**response sequencer에** 올린다(active sequencer는 건드리지 않는다 — `QACTIVE`는
테스트가 필요할 때만 구동한다). 이 시퀀스는 objection을 걸지 않는다 — 무한 루프이므로
objection을 걸면 테스트가 끝나지 않는다.

## 테스트 방법

첫 증분과 달리 이번에는 신호를 구동하므로, 클래스 단위 randomize 검사만으로는
부족하다. **Controller 역할 agent와 Device 역할 agent를 서로 연결한 루프백
테스트벤치**를 만든다.

```
[qch_agent : CONTROLLER] ---- qch_if ---- [qch_agent : DEVICE]
                                 |
                          [qch_agent : PASSIVE]  (관찰 및 검증)
```

DUT 없이 VIP끼리 마주보게 해서, 한쪽이 만든 자극을 다른 쪽이 받고 세 번째 PASSIVE
agent가 관찰한다. 검증 항목:

1. 리셋 해제 직후 신호값이 스펙과 일치 (`QACCEPTn=0`, `QDENY=0`, `QREQn`은 config대로)
2. Controller가 quiescence 요청 → Device가 ACCEPT → `Q_RUN`→`Q_REQUEST`→`Q_STOPPED`
   전이가 PASSIVE monitor에서 순서대로 관측됨
3. Device가 DENY → `Q_RUN`→`Q_REQUEST`→`Q_DENIED`→`Q_CONTINUE`→`Q_RUN` 관측됨
4. `response_delay_cycles`를 N으로 지정했을 때, monitor의 `cycles_in_prev`가 N과
   일치
5. `QCH_ST_ILLEGAL`이 한 번도 관측되지 않음
6. 랜덤 트래픽을 길게 돌렸을 때 6개 상태를 모두 방문

**이 환경에는 SystemVerilog 시뮬레이터가 없다**(`vcs`/`xrun`/`vsim`/`verilator`/
`iverilog` 모두 부재, 확인 완료). 따라서 위 테스트는 작성만 하고 실행은 시뮬레이터가
있는 환경에서 해야 한다. 실행하지 않은 것을 통과로 보고해서는 안 된다.

## 다음 증분으로 미루는 것

- SVA 프로토콜 체커 + bind (handshake rules 6개, illegal 조합, 리셋 상태)
- 커버리지 모델 (상태/전이 커버, `cycles_in_prev` 분포)
- 스코어보드 — 사용 여부 자체가 미정. Q-Channel 신호만으로는 판정 불가능한 항목
  (클럭이 실제로 멈췄는가, 트랜잭션 유실, 데드락)이 대상이 되므로 외부 신호 접근이
  전제된다.
- `qch_ctrl_response_e` 확장, 무응답(stall) 정책, 지연 필드 상한, `UVM_NOCOMPARE`
  — 첫 증분 리뷰에서 미룬 항목들. 소비자가 생길 때 함께 처리한다.
- `QDENY`/`QACTIVE`가 생략된 인터페이스 지원 (IHI0068D §2.1.4)
- P-Channel
