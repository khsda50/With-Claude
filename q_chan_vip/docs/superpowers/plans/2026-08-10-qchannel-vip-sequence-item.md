# Q-Channel VIP sequence_item Implementation Plan

> ## ⚠️ 이 계획서의 Task 2 코드에는 결함이 있었습니다 — 그대로 재실행하지 마세요
>
> Task 2가 지시한 `qch_device_response_item` 코드에 아래 제약이 들어 있었고,
> 이는 **최종 리뷰에서 Critical로 판정되어 커밋 `f02e439`로 수정되었습니다.**
>
> ```systemverilog
> constraint c_accept_delay_meaningful {
>   (policy == QCH_DENY) -> accept_delay_cycles == 0;   // 삭제됨
> }
> ```
>
> **문제:** SystemVerilog는 해공간 전체에 균등 분포하므로, ACCEPT는 조합이 21개
> (지연 0~20), DENY는 1개(지연 0 고정)가 되어 `policy`가 `QCH_DENY`로 randomize
> 될 확률이 50%가 아니라 **약 4.5%**였습니다. deny 핸드셰이크가 22번에 1번만
> 생성됩니다. 또한 `policy==QCH_DENY`에 비0 지연을 지정하는 것이 불가능해져
> "느린 거부" 시나리오를 만들 수 없었습니다.
>
> **수정:** 제약을 삭제하고 `accept_delay_cycles` → `response_delay_cycles`로
> 이름을 바꿔 두 정책 모두에 적용. 단위 테스트도 "한 번이라도 나왔는가"에서
> 개수를 세는 분포 검사로 강화했습니다(기존 테스트는 4.5%로 치우친 상태에서도
> 약 99% 확률로 통과했습니다).
>
> 아래 Task 2 본문은 **당시 실행된 내용 그대로의 기록**입니다. 현재 코드의
> 정답은 `uvm/qch_items.sv`와 갱신된 spec을 보세요.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** AMBA Low Power Interface(IHI0068D) Q-Channel VIP의 stimulus 최소 단위인 sequence_item 클래스 4개를 만든다.

**Architecture:** `qch_item_pkg` 패키지 하나에 `qch_base_item`(공통 필드)과 3개 derived 클래스를 담는다. Controller 역할(`QREQn` 토글)과 Device 역할(accept/deny 정책, `QACTIVE` 토글)이 구동하는 신호와 의사결정 폭이 근본적으로 다르므로 role별로 클래스를 분리한다. 이 아이템들은 순수 자극 표현용이며, 프로토콜 합법성 검사는 하지 않는다.

**Tech Stack:** SystemVerilog, UVM 1.2

## Global Constraints

- 설계 근거 spec: `docs/superpowers/specs/2026-08-10-qchannel-vip-sequence-item-design.md`
- **이 저장소 환경에는 SystemVerilog 시뮬레이터가 없다** (`vcs`/`xrun`/`vsim`/`verilator`/`iverilog` 모두 부재 — 확인 완료). 각 Task의 "Run" 스텝은 **시뮬레이터가 있는 환경에서 실행해야 하며**, 이 저장소에서는 실행 불가다. 실행하지 못했다면 보고서에 반드시 그렇게 적을 것. **실행하지 않은 것을 PASS로 보고하지 말 것.**
- 파일 위치: `uvm/` 디렉토리 (기존 `uvm/simple_test.sv` 와 동일)
- 기존 `uvm/simple_test.sv` 가 `module tb_top` 을 이미 정의한다. 충돌을 피하기 위해 이번 테스트벤치 top 모듈 이름은 **`qch_tb_top`** 을 쓴다.
- **enum label은 전부 `QCH_` 접두사를 붙인다.** spec 초안에는 `ACCEPT`/`DENY`/`ACTIVE_HIGH`/`ACTIVE_LOW` 로 적혀 있으나, 패키지를 `import ...::*` 로 쓰는 환경에서 이런 일반 명칭은 다른 VIP 패키지와 충돌할 위험이 크다. **이것은 spec으로부터의 의도적 이탈이며, 리뷰에서 되돌릴 수 있다.**
- 아이템 클래스는 프로토콜 합법성을 강제하지 않는다. 위반 시퀀스도 만들 수 있게 열어둔다 (검사는 별도 증분의 SVA 몫).
- 주석은 한국어, 기존 `uvm/simple_test.sv` 스타일을 따른다.

---

### Task 1: 패키지 + base item + controller item

**Files:**
- Create: `uvm/qch_items.sv`
- Create: `uvm/qch_items_unit_test.sv`

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces:
  - package `qch_item_pkg`
  - `typedef enum bit { QCH_REQUEST_QUIESCENCE, QCH_ALLOW_RUN } qch_req_action_e;`
  - `typedef enum bit [1:0] { QCH_RSP_NONE, QCH_RSP_ACCEPTED, QCH_RSP_DENIED, QCH_RSP_TIMEOUT } qch_ctrl_response_e;`
  - `class qch_base_item extends uvm_sequence_item;` — 필드 `rand int unsigned pre_delay_cycles;`
  - `class qch_controller_item extends qch_base_item;` — 필드 `rand qch_req_action_e action;`, `rand int unsigned response_timeout_cycles;`, `qch_ctrl_response_e observed_response;`(non-rand), `int unsigned response_latency_cycles;`(non-rand)
  - 테스트 파일: `class qch_item_unit_test extends uvm_test;` 와 `module qch_tb_top;`

- [ ] **Step 1: 실패하는 테스트를 먼저 작성**

`uvm/qch_items_unit_test.sv` 를 아래 내용으로 생성한다.

```systemverilog
// ---------------------------------------------------------------------------
// qch_items_unit_test
//
// qch_item_pkg 의 sequence_item 클래스들에 대한 단위 테스트.
// 신호를 구동하지 않고 객체 생성/랜덤화/제약만 확인한다.
// ---------------------------------------------------------------------------
`include "uvm_macros.svh"
import uvm_pkg::*;
import qch_item_pkg::*;

class qch_item_unit_test extends uvm_test;
  `uvm_component_utils(qch_item_unit_test)

  localparam int N_TRIES = 100;

  function new(string name = "qch_item_unit_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // -------------------------------------------------------------------
  // qch_base_item: pre_delay_cycles 가 soft 범위 안에 들어오고,
  //                 필요하면 override 가능해야 한다.
  // -------------------------------------------------------------------
  task check_base_item();
    qch_base_item it;
    it = qch_base_item::type_id::create("base_it");

    repeat (N_TRIES) begin
      if (!it.randomize())
        `uvm_error("BASE", "randomize() failed on qch_base_item")
      else if (it.pre_delay_cycles > 20)
        `uvm_error("BASE", $sformatf(
          "pre_delay_cycles=%0d is outside soft range [0:20]", it.pre_delay_cycles))
    end

    // soft constraint 이므로 범위 밖 값으로 override 가능해야 한다
    if (!it.randomize() with { pre_delay_cycles == 100; })
      `uvm_error("BASE", "soft constraint on pre_delay_cycles could not be overridden")
    else if (it.pre_delay_cycles != 100)
      `uvm_error("BASE", $sformatf(
        "override failed: pre_delay_cycles=%0d, expected 100", it.pre_delay_cycles))
  endtask

  // -------------------------------------------------------------------
  // qch_controller_item:
  //  - action 이 두 값 모두 나와야 한다
  //  - response_timeout_cycles 가 soft 범위 [10:1000] 안이어야 한다
  //  - 결과 필드(observed_response/response_latency_cycles)는 rand 가 아니므로
  //    randomize() 후에도 초기값을 유지해야 한다
  // -------------------------------------------------------------------
  task check_controller_item();
    qch_controller_item it;
    bit seen_request, seen_allow;

    it = qch_controller_item::type_id::create("ctrl_it");

    if (it.observed_response != QCH_RSP_NONE)
      `uvm_error("CTRL", $sformatf(
        "observed_response should init to QCH_RSP_NONE, got %s", it.observed_response.name()))
    if (it.response_latency_cycles != 0)
      `uvm_error("CTRL", $sformatf(
        "response_latency_cycles should init to 0, got %0d", it.response_latency_cycles))

    repeat (N_TRIES) begin
      if (!it.randomize()) begin
        `uvm_error("CTRL", "randomize() failed on qch_controller_item")
      end
      else begin
        if (it.action == QCH_REQUEST_QUIESCENCE) seen_request = 1;
        if (it.action == QCH_ALLOW_RUN)          seen_allow   = 1;

        if (it.response_timeout_cycles < 10 || it.response_timeout_cycles > 1000)
          `uvm_error("CTRL", $sformatf(
            "response_timeout_cycles=%0d is outside soft range [10:1000]",
            it.response_timeout_cycles))

        // non-rand 결과 필드는 randomize() 가 건드리면 안 된다
        if (it.observed_response != QCH_RSP_NONE)
          `uvm_error("CTRL", "randomize() modified non-rand field observed_response")
        if (it.response_latency_cycles != 0)
          `uvm_error("CTRL", "randomize() modified non-rand field response_latency_cycles")
      end
    end

    if (!seen_request)
      `uvm_error("CTRL", "action never randomized to QCH_REQUEST_QUIESCENCE")
    if (!seen_allow)
      `uvm_error("CTRL", "action never randomized to QCH_ALLOW_RUN")

    // 시퀀스에서 특정 action 을 강제할 수 있어야 한다
    if (!it.randomize() with { action == QCH_REQUEST_QUIESCENCE; })
      `uvm_error("CTRL", "could not constrain action to QCH_REQUEST_QUIESCENCE")
    else if (it.action != QCH_REQUEST_QUIESCENCE)
      `uvm_error("CTRL", "action constraint did not take effect")
  endtask

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "=== qch item unit test start ===", UVM_LOW)

    check_base_item();
    check_controller_item();

    `uvm_info(get_type_name(), "=== qch item unit test done ===", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass

// ---------------------------------------------------------------------------
// 시뮬레이션 entry point
// (uvm/simple_test.sv 가 tb_top 을 쓰므로 이름을 달리한다)
// ---------------------------------------------------------------------------
module qch_tb_top;
  initial begin
    run_test("qch_item_unit_test");
  end
endmodule
```

- [ ] **Step 2: 테스트를 실행해서 실패를 확인**

Run:
```bash
vcs -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps uvm/qch_items_unit_test.sv -o simv_qch
```

Expected: **컴파일 FAIL.** `qch_item_pkg` 가 아직 없으므로 `import qch_item_pkg::*;` 에서 "Unable to find package" 류의 에러가 난다.

시뮬레이터가 없는 환경이면 이 스텝을 실행할 수 없다. 그 사실을 보고서에 적고 다음 스텝으로 넘어간다. **실행하지 않은 것을 PASS/FAIL로 지어내지 말 것.**

- [ ] **Step 3: 패키지와 두 클래스를 구현**

`uvm/qch_items.sv` 를 아래 내용으로 생성한다.

```systemverilog
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

endpackage
```

- [ ] **Step 4: 테스트를 실행해서 통과를 확인**

Run:
```bash
vcs -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps uvm/qch_items.sv uvm/qch_items_unit_test.sv -o simv_qch
```
그다음:
```bash
./simv_qch +UVM_TESTNAME=qch_item_unit_test
```

Expected: 컴파일 성공, 실행 후 UVM 리포트 요약에 `UVM_ERROR : 0` 그리고 `UVM_FATAL : 0`. 로그에 `=== qch item unit test done ===` 가 찍힌다.

시뮬레이터가 없어 실행하지 못했다면 보고서에 그렇게 적는다.

- [ ] **Step 5: 커밋**

```bash
git add uvm/qch_items.sv uvm/qch_items_unit_test.sv
git commit -m "Add Q-Channel VIP base and controller sequence items"
```

---

### Task 2: device 아이템 2종

**Files:**
- Modify: `uvm/qch_items.sv` (package 안에 클래스 2개 추가)
- Modify: `uvm/qch_items_unit_test.sv` (검사 task 2개 추가 + run_phase 에서 호출)

**Interfaces:**
- Consumes: Task 1이 만든 `qch_item_pkg`, `qch_base_item`, 그리고 테스트 파일의 `qch_item_unit_test` / `qch_tb_top`
- Produces:
  - `typedef enum bit { QCH_ACCEPT, QCH_DENY } qch_device_policy_e;`
  - `typedef enum bit { QCH_ACTIVE_HIGH, QCH_ACTIVE_LOW } qch_active_action_e;`
  - `class qch_device_response_item extends qch_base_item;` — 필드 `rand qch_device_policy_e policy;`, `rand int unsigned accept_delay_cycles;`
  - `class qch_device_active_item extends qch_base_item;` — 필드 `rand qch_active_action_e action;`

- [ ] **Step 1: 실패하는 테스트를 먼저 작성**

`uvm/qch_items_unit_test.sv` 의 `check_controller_item()` endtask 바로 다음 줄에 아래 두 task 를 삽입한다.

```systemverilog
  // -------------------------------------------------------------------
  // qch_device_response_item:
  //  - policy 가 두 값 모두 나와야 한다
  //  - accept_delay_cycles 는 soft 범위 [0:20] 안이어야 한다
  //  - policy==QCH_DENY 이면 accept_delay_cycles 는 항상 0 이어야 한다
  //    (DENY 일 때 accept 지연은 의미가 없으므로 아이템을 모호하지 않게 만든다)
  // -------------------------------------------------------------------
  task check_device_response_item();
    qch_device_response_item it;
    bit seen_accept, seen_deny;

    it = qch_device_response_item::type_id::create("dev_rsp_it");

    repeat (N_TRIES) begin
      if (!it.randomize()) begin
        `uvm_error("DEVRSP", "randomize() failed on qch_device_response_item")
      end
      else begin
        if (it.policy == QCH_ACCEPT) seen_accept = 1;
        if (it.policy == QCH_DENY)   seen_deny   = 1;

        if (it.accept_delay_cycles > 20)
          `uvm_error("DEVRSP", $sformatf(
            "accept_delay_cycles=%0d is outside soft range [0:20]", it.accept_delay_cycles))

        if (it.policy == QCH_DENY && it.accept_delay_cycles != 0)
          `uvm_error("DEVRSP", $sformatf(
            "accept_delay_cycles=%0d must be 0 when policy==QCH_DENY",
            it.accept_delay_cycles))
      end
    end

    if (!seen_accept) `uvm_error("DEVRSP", "policy never randomized to QCH_ACCEPT")
    if (!seen_deny)   `uvm_error("DEVRSP", "policy never randomized to QCH_DENY")

    // ACCEPT 로 강제하고 지연도 지정할 수 있어야 한다
    if (!it.randomize() with { policy == QCH_ACCEPT; accept_delay_cycles == 7; })
      `uvm_error("DEVRSP", "could not constrain policy=QCH_ACCEPT with accept_delay_cycles=7")
    else if (it.policy != QCH_ACCEPT || it.accept_delay_cycles != 7)
      `uvm_error("DEVRSP", "policy/accept_delay_cycles constraint did not take effect")
  endtask

  // -------------------------------------------------------------------
  // qch_device_active_item:
  //  - action 이 두 값 모두 나와야 한다
  //  - QACTIVE 는 handshake 와 독립이므로 다른 필드에 대한 제약이 없다
  // -------------------------------------------------------------------
  task check_device_active_item();
    qch_device_active_item it;
    bit seen_high, seen_low;

    it = qch_device_active_item::type_id::create("dev_act_it");

    repeat (N_TRIES) begin
      if (!it.randomize()) begin
        `uvm_error("DEVACT", "randomize() failed on qch_device_active_item")
      end
      else begin
        if (it.action == QCH_ACTIVE_HIGH) seen_high = 1;
        if (it.action == QCH_ACTIVE_LOW)  seen_low  = 1;
      end
    end

    if (!seen_high) `uvm_error("DEVACT", "action never randomized to QCH_ACTIVE_HIGH")
    if (!seen_low)  `uvm_error("DEVACT", "action never randomized to QCH_ACTIVE_LOW")

    if (!it.randomize() with { action == QCH_ACTIVE_HIGH; })
      `uvm_error("DEVACT", "could not constrain action to QCH_ACTIVE_HIGH")
    else if (it.action != QCH_ACTIVE_HIGH)
      `uvm_error("DEVACT", "action constraint did not take effect")
  endtask
```

그리고 같은 파일의 `run_phase` 안에서 `check_controller_item();` 다음 줄에 아래 두 줄을 추가한다.

```systemverilog
    check_device_response_item();
    check_device_active_item();
```

- [ ] **Step 2: 테스트를 실행해서 실패를 확인**

Run:
```bash
vcs -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps uvm/qch_items.sv uvm/qch_items_unit_test.sv -o simv_qch
```

Expected: **컴파일 FAIL.** `qch_device_response_item` / `qch_device_active_item` / `QCH_ACCEPT` 등이 아직 패키지에 없으므로 "not declared" 류의 에러가 난다.

시뮬레이터가 없으면 실행 불가임을 보고서에 적는다.

- [ ] **Step 3: 두 클래스를 구현**

`uvm/qch_items.sv` 에서, `qch_ctrl_response_e` typedef 블록 바로 다음에 아래 두 enum 을 추가한다.

```systemverilog
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
```

그리고 `qch_controller_item` 클래스의 `endclass` 다음, `endpackage` 앞에 아래 두 클래스를 추가한다.

```systemverilog
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

    // QREQn 하강을 감지한 뒤 QACCEPTn 을 LOW 로 내리기까지의 대기 사이클.
    rand int unsigned accept_delay_cycles;

    constraint c_accept_delay { soft accept_delay_cycles inside {[0:20]}; }

    // DENY 일 때 accept 지연은 의미가 없다. 0 으로 고정해서 아이템이
    // 모호하게 출력되지 않도록 한다.
    constraint c_accept_delay_meaningful {
      (policy == QCH_DENY) -> accept_delay_cycles == 0;
    }

    `uvm_object_utils_begin(qch_device_response_item)
      `uvm_field_enum(qch_device_policy_e, policy,              UVM_ALL_ON)
      `uvm_field_int (accept_delay_cycles,                      UVM_ALL_ON | UVM_DEC)
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
```

- [ ] **Step 4: 테스트를 실행해서 통과를 확인**

Run:
```bash
vcs -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps uvm/qch_items.sv uvm/qch_items_unit_test.sv -o simv_qch
```
그다음:
```bash
./simv_qch +UVM_TESTNAME=qch_item_unit_test
```

Expected: 컴파일 성공, `UVM_ERROR : 0` 및 `UVM_FATAL : 0`. 로그에 `=== qch item unit test done ===`.

시뮬레이터가 없어 실행하지 못했다면 보고서에 그렇게 적는다.

- [ ] **Step 5: 커밋**

```bash
git add uvm/qch_items.sv uvm/qch_items_unit_test.sv
git commit -m "Add Q-Channel VIP device response and active sequence items"
```
