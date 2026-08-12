# Q-Channel VIP — env 및 bind 어댑터

대상: `qch_env.svh`, `qch_bind.sv`, `qch_seq_lib.svh`, `qch_env_example.sv`, `qch.f`
선행 증분: sequence_item 설계, driver/monitor 설계, coverage 모델

## 배경

지금까지 이 VIP 는 agent 까지만 있었고, 붙이는 쪽이 다음을 직접 해야 했다.

1. `qch_config` 를 만들어 config_db 에 경로 맞춰 넣기
2. `virtual qch_if` 를 config_db 에 넣기 — 채널이 두 개면 경로를 나눠서
3. agent 를 생성하고 sequencer 핸들을 찾아 들어가기
4. monitor 의 analysis port 를 agent 내부에서 꺼내기

자체 테스트 5 종은 전부 monitor/driver 를 직접 인스턴스하거나 전역 `"*"` 로
config_db 를 뿌리는 형태였다. 단위 테스트에는 맞지만 **실제 DUT 에 붙일 때는
쓸 수 없다** — 채널이 둘 이상이면 전역 설정이 서로 덮어쓴다.

이 증분의 목적은 붙이는 쪽의 할 일을 **"cfg 하나 넘기고 sequencer 쓰기"** 로 줄이는 것.

## 설계

### 1. env 가 config_db 배선을 흡수한다

`qch_env` 는 자기 subtree 에만 cfg 와 vif 를 내려보낸다.

```systemverilog
uvm_config_db#(qch_config)::set(this, "*", "cfg", cfg);
uvm_config_db#(virtual qch_if)::set(this, "*", "vif", cfg.vif);
```

전역 `set(null, "*", ...)` 을 쓰지 않는 것이 핵심이다. 채널이 여러 개일 때
**env 인스턴스마다 다른 인터페이스를 잡을 수 있어야** 하고, 그것이 이 VIP 를
실제 SoC 에 붙일 수 있게 하는 최소 조건이다.

### 2. vif 를 config 객체에 넣는다

`qch_config` 에 `virtual qch_if vif` 를 추가했다. 상위가 `"cfg"` 와 `"vif"` 를
따로 넣지 않고 cfg 하나만 채우면 된다.

`uvm_field_*` 매크로는 붙이지 않는다. virtual interface 는 field automation 의
copy/compare/print 대상이 될 수 없다.

호환을 위해 config_db 경로도 남겨 뒀다. `cfg.vif` 가 null 이면 env 가
config_db 에서 `"vif"` 를 찾아 `cfg.vif` 에 채운다. 기존 테스트가 쓰던 전역
`"*"` 설정이 그대로 동작한다.

### 3. cfg 전달은 핸들 대입도 허용한다

```systemverilog
env_ctrl     = qch_env::type_id::create("env_ctrl", this);
env_ctrl.cfg = cfg_ctrl;   // config_db 없이
```

`build_phase` 가 top-down 이므로 상위가 env 를 만든 뒤 대입하는 시점이 env 의
`build_phase` 보다 앞이다. config_db 경로(`get(this,"","cfg")`)도 그대로 둬서
둘 중 편한 쪽을 쓸 수 있다.

### 4. sequencer 핸들은 connect_phase 에서 올린다

`build_phase` 에서는 불가능하다. agent 의 sequencer 는 agent 의 `build_phase` 에서
만들어지고 그것은 env 의 `build_phase` 보다 나중이다. `connect_phase` 는 bottom-up
이라 `agent.connect → env.connect → 상위.connect` 순서가 보장되므로, 상위가
`env.ctrl_seqr` 를 볼 시점에는 이미 채워져 있다.

role 에 따라 일부는 null 로 남는다 (CONTROLLER: ctrl_seqr / DEVICE: rsp_seqr,
act_seqr / PASSIVE: 없음). monitor 의 analysis port 는 `env.ap` 로 올려, 상위
scoreboard 가 agent 내부를 모르고도 붙을 수 있게 했다.

### 5. bind 어댑터를 역할별로 셋 나눈다

`qch_if` 의 4 개 신호는 인터페이스 내부 변수라서 `bind` 로 DUT 신호에 직접 이을 수
없다. 포트를 가진 얇은 모듈을 두고 그 안에서 `qch_if` 를 인스턴스한다.

역할별로 나눈 이유는 **방향** 이다. SystemVerilog 는 같은 변수에 절차적 대입
(driver 의 `vif.QREQn <= ...`)과 연속 대입(`assign`)을 동시에 하는 것을 금지한다.
따라서 VIP 가 구동하는 신호는 인터페이스에서 읽어 나가고, 관측하는 신호는
인터페이스로 밀어넣는다. 어느 쪽인지는 role 이 정하므로 모듈이 셋이 된다.

| 모듈 | VIP 역할 | 쓰는 상황 |
|---|---|---|
| `qch_bind_controller` | QREQn 구동 | CRMU 가 아직 없을 때 |
| `qch_bind_device` | QACCEPTn/QDENY/QACTIVE 구동 | CPU 측 responder 가 없을 때 |
| `qch_bind_passive` | 구동 없음 | 양쪽 RTL 이 다 있을 때 (커버리지·체커) |

### 6. 인터페이스 핸들 전달은 TB top 의 initial 에서 한다

어댑터 모듈 안에서 `config_db::set` 을 하지 않는다. 모듈의 `initial` 블록이
`run_test()` 의 `build_phase` 보다 먼저 실행되는지는 시뮬레이터 구현에 달려 있고,
늦으면 "vif 가 없다" fatal 로 끝나 원인 추적이 번거롭다.

대신 어댑터는 `u_qch_if` 를 노출만 하고, TB top 이 `run_test()` **직전에** 계층
참조로 넘긴다. 같은 `initial` 블록 안이라 순서가 결정적이다.

### 7. 시퀀스를 테스트에서 떼어 패키지로 옮긴다

시퀀스가 테스트 파일 안에만 있어 다른 환경에서 쓸 수 없었다. 전부 `qch_seq_lib.svh`
로 옮기고, 세 시퀀스가 똑같이 반복하던 create → start_item → randomize →
finish_item → 결과 집계를 `qch_ctrl_base_seq` 로 뺐다.

| 시퀀스 | 대상 sequencer | 출처 |
|---|---|---|
| `qch_ctrl_base_seq` | ctrl_seqr | 신규 (공통 동작) |
| `qch_quiesce_seq` | ctrl_seqr | 신규 (일반 회귀) |
| `qch_ctrl_smoke_seq` | ctrl_seqr | `qch_controller_test.sv` 에서 이동 |
| `qch_loopback_seq` | ctrl_seqr | `qch_loopback_test.sv` 에서 이동 |
| `qch_fixed_delay_seq` | rsp_seqr | `qch_loopback_test.sv` 에서 이동 |
| `qch_deny_seq` | rsp_seqr | 신규 (deny 경로 강제) |
| `qch_active_toggle_seq` | act_seqr | 신규 |
| `qch_responder_seq` | rsp_seqr | 기존 (agent 가 자동 기동, 별도 파일 유지) |

이동한 세 개는 기존 테스트가 필드를 직접 읽으므로 **API 를 그대로 유지했다**
(`qch_ctrl_smoke_seq.sent`, `qch_loopback_seq.n_rounds`,
`qch_fixed_delay_seq.fixed_delay`). 테스트 쪽은 정의만 지웠다.

`qch_active_toggle_seq` 를 새로 만든 이유: `act_seqr` 를 쓰는 시퀀스가 하나도
없었다. QACTIVE 를 흔들지 않으면 커버리지의 `cp_qactive` 와 `x_response_qactive` 가
절반만 찬다. `qch_deny_seq` 도 같은 성격으로, `x_response_latency` 의
`denied × medium` 같은 hole 을 겨냥한다.

요청 뒤에 항상 `QCH_ALLOW_RUN` 을 붙인다. IHI0068D 는 QDENY 가 QREQn 이 HIGH 로
되돌아온 뒤에만 LOW 로 내려갈 수 있다고 정하므로, **거부되었을 때 요청을 되돌리는
것은 선택이 아니라 의무** 다. 수락된 경우도 Q_STOPPED → Q_EXIT → Q_RUN 정상 경로라
두 경우가 같은 모양이 된다.

`randomize() with {}` 안에서 `local::` 을 쓰지 않는다. 인자·멤버 이름을 아이템
필드와 겹치지 않게 지어(`act_arg`, `delay_arg`, `timeout_cycles`) 평범한 이름 해석으로
충분하게 만들었다. `local::` 지원이 툴마다 미묘한 것을 피하려는 것이다.

### 8. 채널이 여러 개일 때 — env 를 여러 개 두고 컨테이너로 묶는다

**채널마다 `qch_env` 하나** 라는 구조는 유지한다. cfg/vif 를 env subtree 로만
내려보내는 격리가 채널이 섞이지 않는 근거이고, 그것을 포기하면 안 된다.

문제는 테스트 쪽 반복이다. 채널이 늘 때마다 cfg 생성·vif 조회·env 생성·시퀀스
start 가 같이 늘어난다. 그래서 두 겹을 더 얹었다.

**`qch_multi_config` / `qch_multi_env`** — 채널을 이름으로 등록하면 env 를 대신
만든다. 등록 순서를 `names[$]` 로 보존하는데, 연관 배열의 `foreach` 순회는 키의
사전순이라 **전력 시퀀스 순서로 쓸 수 없기** 때문이다.

```systemverilog
void'(mcfg.add("cpu", QCH_ROLE_CONTROLLER, vif_cpu));
void'(mcfg.add("l2",  QCH_ROLE_CONTROLLER, vif_l2 ));
menv.cfg = mcfg;
```

**`qch_virtual_sequencer`** — 채널별 sequencer 핸들만 들고 있는 통로.
전력 관리에서 "무엇을 먼저 조용히 시키는가" 는 채널 하나만 보는 시퀀스로 표현할 수
없다. 채널을 넘나드는 시퀀스가 필요하고, 그것이 올라갈 자리가 이것이다.

인덱스가 아니라 **이름으로 찾는다.** 인덱스로 찾으면 채널이 하나 늘거나 순서가
바뀔 때 시퀀스가 조용히 다른 채널을 건드린다. `get_ctrl()` 은 없는 이름에
`uvm_fatal` 을 낸다 — null sequencer 에 `start` 하면 원인과 먼 곳에서 죽는다.

**`qch_vseq_lib.svh`** — `qch_quiesce_all_seq`(전 채널, 순차/동시 선택),
`qch_quiesce_order_seq`(지정 순서). 후자가 전력 시퀀스의 실제 모양이다.
`order` 가 비면 `uvm_fatal` 로 잡는다. 조용히 통과하면 시나리오가 돌았다고
착각하게 된다.

동시 모드의 `fork` 는 반복마다 새 `automatic` 변수를 이름 있는 블록
(`begin : spawn_per_channel`)에 둔다. 이름 없는 블록의 선언을 거부하는 툴을 피하려는
것이다.

## 상위가 하는 일

**채널 하나**

```systemverilog
// build_phase
cfg      = qch_config::type_id::create("cfg");
cfg.role = QCH_ROLE_CONTROLLER;
cfg.vif  = <bind 어댑터의 u_qch_if>;
env      = qch_env::type_id::create("env", this);
env.cfg  = cfg;

// run_phase
seq.start(env.ctrl_seqr);
```

**채널 여러 개**

```systemverilog
// build_phase
mcfg = qch_multi_config::type_id::create("mcfg");
void'(mcfg.add("cpu", QCH_ROLE_CONTROLLER, vif_cpu));
void'(mcfg.add("l2",  QCH_ROLE_CONTROLLER, vif_l2 ));
void'(mcfg.add("noc", QCH_ROLE_CONTROLLER, vif_noc));
menv     = qch_multi_env::type_id::create("menv", this);
menv.cfg = mcfg;

// run_phase — 순서를 쓰는 시나리오
vseq       = qch_quiesce_order_seq::type_id::create("vseq");
vseq.order = '{"cpu", "l2", "noc"};
vseq.start(menv.vseqr);

// 한 채널만
seq.start(menv.get_ctrl("cpu"));
```

## 미확인 사항

> **이 환경에는 SystemVerilog 시뮬레이터가 없다.** 이 증분도 **컴파일되지 않았다.**
> 첫 컴파일에서 걸릴 만한 곳:
>
> - `randomize() with { pre_delay_cycles == local::gap_cycles; }` — `local::`
>   스코프 한정자 지원
> - `assign` 으로 인터페이스 내부 변수를 구동하는 것 (변수에 대한 연속 대입)
> - bind 대상 DUT 입력 포트에 기존 구동자(tie-off)가 있으면 다중 구동 에러
> - `qch_env_example.sv` 는 계층 경로가 비어 있어 그대로는 컴파일되지 않는다
>   (`QCH_EXAMPLE_TB` 미정의 시 TB top 은 빠진다)

## 다음 증분

- SVA 프로토콜 체커 + bind (handshake rules, illegal 조합, 리셋 상태)
- QDENY/QACTIVE 생략 구성 지원 (IHI0068D 2.1.4) — 실제 DUT 에 이 구성이 있으면 필요
- scoreboard — Q-Channel 신호만으로 판정 불가능한 항목(클럭이 실제로 멈췄는가)이
  대상이라 외부 신호 접근이 전제된다
