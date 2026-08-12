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

### 7. 재사용 가능한 controller 시퀀스를 패키지로 옮긴다

controller 시퀀스가 지금까지 테스트 파일 안에만 있어(`qch_ctrl_smoke_seq`,
`qch_loopback_seq`) 다른 환경에서 쓸 수 없었다. `qch_quiesce_seq` 를 패키지에 둔다.

요청 뒤에 항상 `QCH_ALLOW_RUN` 을 붙인다. IHI0068D 는 QDENY 가 QREQn 이 HIGH 로
되돌아온 뒤에만 LOW 로 내려갈 수 있다고 정하므로, **거부되었을 때 요청을 되돌리는
것은 선택이 아니라 의무** 다. 수락된 경우도 Q_STOPPED → Q_EXIT → Q_RUN 정상 경로라
두 경우가 같은 모양이 된다.

Device 측은 필요 없다. agent 가 `cfg.start_responder_seq` 로 `qch_responder_seq` 를
자동으로 올린다.

## 상위가 하는 일

```systemverilog
// build_phase
cfg          = qch_config::type_id::create("cfg");
cfg.role     = QCH_ROLE_CONTROLLER;
cfg.vif      = <bind 어댑터의 u_qch_if>;
env          = qch_env::type_id::create("env", this);
env.cfg      = cfg;

// run_phase
seq.start(env.ctrl_seqr);
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
