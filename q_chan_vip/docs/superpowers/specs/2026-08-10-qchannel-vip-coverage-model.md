# Q-Channel VIP — functional coverage 모델

대상: `qch_coverage.svh`, `qch_coverage_test.sv`, `qch_items.sv`(어휘 추가)
선행 증분: sequence_item 설계, driver/monitor 설계

## 배경

sequence_item 설계 문서 §8 에 커버리지 모델 초안이 있었다. 그런데 그 초안은
**당시 검토 중이던 아이템 형태**를 전제로 쓰여 있고, 이후 driver/monitor 증분에서
확정된 `qch_monitor_item` 과 필드가 맞지 않는다.

| §8 초안이 쓴 필드 | 실제 `qch_monitor_item` | 해결 |
|---|---|---|
| `item.response` | 없음 | `(prev_state, state)` 로부터 파생 |
| `item.resp_latency` | 없음 | `cycles_in_prev` (Q_REQUEST 를 떠날 때) |
| `item.qactive_at_req` / `qactive_during` | `qactive` 하나 | 전이 시점 값 하나 + prev_state guard |
| `item.idle_before` | 없음 | `cycles_in_prev` (Q_RUN 을 떠날 때) |
| `cur_state` transition bin | `prev_state`/`state` 쌍 | 쌍으로 판정 (아래 참조) |

초안대로 아이템에 필드를 더 붙이는 선택도 있었지만 그렇게 하지 않았다.
확정된 아이템이 이미 필요한 정보를 다 들고 있고, `cycles_in_prev` 하나가 문맥에 따라
세 가지 뜻을 겸하기 때문이다.

- Q_REQUEST 를 떠날 때 → **device 응답 지연**
- Q_RUN 을 떠날 때 → **요청 전 유휴 시간**
- Q_STOPPED 를 떠날 때 → **조용히 머문 시간**

즉 필드를 늘리는 대신 **샘플 조건(guard)이 지표를 가른다.** 같은 값을 prev_state 로
걸러 세 개의 커버포인트로 나눴다.

## 설계 결정

### 1. 전이 판정을 transition bin 으로 하지 않는다

covergroup 의 `bins t = (A => B)` 는 **연속된 두 sample 사이의 이력**에 의존한다.
monitor 는 리셋 중 발행을 멈추므로, 리셋을 걸친 두 아이템이 인접 sample 로 들어오면
실제로 일어나지 않은 전이가 하나 잡힌다.

아이템이 `prev_state` 를 이미 들고 있으니 **아이템 하나로 판정**하면 이력에 의존하지
않는다. 그래서 `qch_classify_trans(prev_state, state)` 로 쌍을 이름 있는 전이로 접고,
그 enum 을 커버포인트로 쓴다.

부수 효과로 지표가 깨끗해진다. `prev_state × state` 를 그대로 cross 하면 7×7=49 칸이
생기고 그중 7 개만 합법이라 달성률이 희석된다. enum 으로 접으면 **합법 7 개 +
`QCH_TRANS_OTHER`** 8 칸이 되고, 목표는 "앞의 7 개를 채우고 OTHER 는 0" 으로 명확해진다.

### 2. `QCH_ST_ILLEGAL` 을 `illegal_bins` 로 두지 않는다

`illegal_bins` 는 hit 되는 순간 시뮬레이터가 에러를 낸다. 이 VIP 는 **검사는 SVA,
관측은 monitor/coverage** 로 역할을 나눴고, monitor 도 ILLEGAL 진입에 `uvm_error` 를
내지 않는다(설계 문서 명시). 커버리지에서 에러를 내면 같은 사실을 두 곳에서 관리하게
되고 SVA 증분과 중복된다.

그래서 보통 bin `illegal` 로 두고 **회귀 리포트에서 0 이 아니면 눈에 띄게** 한다.
`cp_response` 의 `other` bin(응답 없이 Q_REQUEST 이탈)과 `cp_trans` 의
`QCH_TRANS_OTHER` 도 같은 성격이다 — **채워야 할 칸이 아니라 0 이어야 하는 칸.**

### 3. cross 는 guard 를 공유하는 커버포인트끼리만 만든다

`cp_response` / `cp_resp_latency` / `cp_qactive_at_resp` 는 모두
`iff (prev_state == QCH_ST_REQUEST)` 를 쓴다. guard 가 같으면 셋 다 같은 전이에서만
샘플되므로, 이들 사이의 cross 에 "일어날 수 없는 조합" 이 생기지 않는다.

guard 가 다른 커버포인트를 cross 하면 구조적으로 도달 불가능한 칸이 목표에 섞여
`ignore_bins` 로 걷어내는 작업이 따라붙는다. 애초에 만들지 않는 쪽을 골랐다.

### 4. 아이템 핸들이 아니라 스칼라를 sample 인자로 넘긴다

`with function sample(...)` 에 아이템 핸들을 넘기고 커버포인트 식에서 역참조하는
형태는 시뮬레이터 간 지원 차이가 있다. 인자로 받은 스칼라만 쓰는 편이 이식성이 좋다.

## 커버리지 항목

전부 **monitor 아이템**에서 샘플한다. 자극 아이템을 쓰지 않는 이유: VIP 가
`QCH_ROLE_PASSIVE` 로 쓰이면 자극 아이템이 생성되지 않아 커버리지가 전부 0 이 된다.
"무엇을 하려 했는가" 가 아니라 "무엇이 일어났는가" 를 세는 쪽만 role 과 무관하게 성립한다.

| 커버포인트 | guard | bin | 목표 |
|---|---|---|---|
| `cp_state` | – | 6 개 합법 상태 + `illegal` | 6 개 채움, illegal 0 |
| `cp_trans` | – | 합법 7 개 + `OTHER` | 7 개 채움, OTHER 0 |
| `cp_qactive` | – | low / high | 둘 다 |
| `cp_response` | prev=REQUEST | accepted / denied / other | 앞 둘 채움, other 0 |
| `cp_resp_latency` | prev=REQUEST | one(1) / short(2–7) / medium(8–31) / long(32+) | 4 개 |
| `cp_qactive_at_resp` | prev=REQUEST | low / high | 둘 다 |
| `cp_run_before_req` | RUN→REQUEST | tight(1) / short(2–7) / spaced(8+) | 3 개 |
| `cp_stopped_dwell` | prev=STOPPED | brief(1–3) / short(4–15) / long(16+) | 3 개 |
| `x_response_latency` | prev=REQUEST | 3×4 = 12 | other 행 4 칸 제외 8 칸 |
| `x_response_qactive` | prev=REQUEST | 3×2 = 6 | other 행 2 칸 제외 4 칸 |

`cycles_in_prev` 의 최소 bin 이 0 이 아니라 1 인 이유: monitor 는 상태 진입 시
카운터를 1 로 시작해 매 클럭 올린다. 0 은 구조상 나올 수 없다.

### `x_response_qactive` 가 이 설계의 근거

QACTIVE 를 handshake 종속 필드로 설계했다면(sequence_item 설계 §4.1 에서 기각한 선택지)
"요청과 무관한 wakeup" 을 표현할 수 없어 이 cross 자체가 만들어지지 않는다.
**아이템이 표현하지 못하는 현상은 커버리지가 볼 수 없다.**

## 테스트

`qch_coverage_test.sv` — 두 층으로 나눴다.

1. **분류 함수 전수 검사** — `qch_classify_trans` / `qch_classify_response` 를
   7×7=49 쌍 전부에 대해 독립 기술한 기대값과 비교하고, 이름 있는 전이가 정확히
   7 개인지 개수까지 못 박는다. 커버리지 엔진과 무관하게 항상 판정 가능한 부분.

2. **샘플링 경로 검사** — accept 왕복 3 회 + deny 왕복 2 회를 지향 구동해
   전이 20 개를 만들고, monitor 발행 수와 coverage 샘플 수 일치, 전이 순서,
   응답 지연 값(1 / 4 / 10 / 40), 응답 시점 QACTIVE(accept·deny 각각 low/high)를 확인한다.
   지연 값을 직접 못 박는 이유: 값이 어긋나면 엉뚱한 bin 에 들어가는데 커버리지
   리포트만 봐서는 알아채기 어렵다.

bin 단위 hit 여부는 단정하지 않는다. `get_inst_coverage()` 는 커버리지 수집을 켜고
컴파일했을 때만 의미 있는 값을 돌려주므로, 에러 조건으로 쓰면 옵션 없이 돌린 회귀에서
거짓 실패가 난다. 값은 로그로만 남긴다.

> **이 환경에는 SystemVerilog 시뮬레이터가 없다** (`vcs`/`xrun`/`vsim`/`verilator`/
> `iverilog` 전부 부재, 재확인). 위 테스트는 작성만 되어 있고 **실행되지 않았다.**
> 실행하지 않은 것을 통과로 보고해서는 안 된다.

## 다음 증분

- 시뮬레이터 있는 환경에서 컴파일·실행 → `qch_coverage_test` 통과 확인
- 랜덤 회귀 → hole 분석 → directed sequence 추가 → **closure**
  - 지향 테스트가 남기는 hole: `accepted × long`, `denied × one`, `denied × medium`
- SVA 프로토콜 체커 (handshake rules, illegal 조합) — `illegal`/`OTHER` bin 이 0 임을
  보증하는 쪽은 이 증분이 아니라 SVA 의 몫
- `cp_stopped_dwell` 의 bin 경계는 임시값이다. 실제 DUT 의 전력 시퀀스 지연 분포를
  보고 조정해야 한다.
