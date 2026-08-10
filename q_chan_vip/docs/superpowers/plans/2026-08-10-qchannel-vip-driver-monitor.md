# Q-Channel VIP driver / monitor / agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Q-Channel(IHI0068D) VIP의 인터페이스, monitor, 양방향 driver, agent를 만들어 실제 신호를 구동하고 관찰할 수 있게 한다.

**Architecture:** `qch_if` 인터페이스에 modport로 신호 소유권을 나눈다. `qch_agent` 하나가 config의 `role`(CONTROLLER/DEVICE/PASSIVE)을 보고 필요한 driver와 sequencer만 만든다. Device 역할은 sequencer 두 개(응답용/QACTIVE용)를 써서 두 흐름이 서로 막지 않게 한다. monitor는 신호에서 상태를 복원해 발행만 하고 위반 판정은 하지 않는다.

**Tech Stack:** SystemVerilog, UVM 1.2

## Global Constraints

- 설계 근거 spec: `docs/superpowers/specs/2026-08-10-qchannel-vip-driver-monitor-design.md`
- **이 저장소 환경에는 SystemVerilog 시뮬레이터가 없다** (`vcs`/`xrun`/`vsim`/`verilator`/`iverilog` 모두 부재 — 확인 완료). 각 Task의 "Run" 스텝은 시뮬레이터가 있는 환경에서 실행해야 하며 여기서는 실행 불가다. **실행하지 않은 것을 PASS로 보고하지 말 것.** 실행하지 못했다면 보고서에 그렇게 적을 것.
- 파일 위치: `uvm/` 디렉토리
- 기존 `uvm/simple_test.sv`가 `module tb_top`을, `uvm/qch_items_unit_test.sv`가 `module qch_tb_top`을 이미 정의한다. 이번에 만드는 top 모듈은 이름이 달라야 한다.
- enum label은 전부 `QCH_` 접두사를 붙인다 (기존 `qch_item_pkg` 규칙과 동일).
- monitor는 프로토콜 위반을 보고하지 않는다. `QCH_ST_ILLEGAL`도 상태로 발행만 하고 `uvm_error`를 내지 않는다. 검사는 별도 SVA 증분 몫이다.
- 주석은 한국어, 기존 `uvm/qch_items.sv` 스타일을 따른다.
- **이번 증분은 트랜잭션 도중 리셋을 지원하지 않는다.** driver는 리셋 해제를 한 번 기다린 뒤 아이템 루프에 들어간다. 이 제약을 각 driver 주석에 명시한다.
- driver/monitor의 virtual interface는 **modport로 한정된 타입**(`virtual qch_if.controller` 등)을 쓴다. config_db에는 한정 없는 `virtual qch_if`를 저장하고 각 컴포넌트가 대입해서 좁힌다. 시뮬레이터가 이 대입을 거부하면 모든 컴포넌트에서 한정 없는 `virtual qch_if`로 바꾸는 것이 대체안이다.

---

### Task 1: 인터페이스 + 상태 표현 + monitor

**Files:**
- Create: `uvm/qch_if.sv`
- Modify: `uvm/qch_items.sv` (package 안에 enum/함수/클래스 추가)
- Create: `uvm/qch_config.svh`
- Create: `uvm/qch_monitor.svh`
- Create: `uvm/qch_agent_pkg.sv`
- Create: `uvm/qch_monitor_test.sv`

**Interfaces:**
- Consumes: 기존 `qch_item_pkg` (`qch_base_item` 등)
- Produces:
  - `interface qch_if (input logic clk, input logic rst_n);` — 신호 `QREQn`/`QACCEPTn`/`QDENY`/`QACTIVE`, modport `controller`/`device`/`monitor`
  - `typedef enum bit [2:0] { QCH_ST_RUN, QCH_ST_REQUEST, QCH_ST_STOPPED, QCH_ST_EXIT, QCH_ST_DENIED, QCH_ST_CONTINUE, QCH_ST_ILLEGAL } qch_state_e;`
  - `function automatic qch_state_e qch_decode_state(bit qreqn, bit qacceptn, bit qdeny);`
  - `class qch_monitor_item extends uvm_sequence_item;` — 필드 `qch_state_e prev_state; qch_state_e state; bit qactive; int unsigned cycles_in_prev;` (모두 non-rand)
  - `typedef enum bit [1:0] { QCH_ROLE_CONTROLLER, QCH_ROLE_DEVICE, QCH_ROLE_PASSIVE } qch_role_e;`
  - `class qch_config extends uvm_object;` — 필드 `qch_role_e role`(기본 `QCH_ROLE_PASSIVE`), `bit start_responder_seq`(기본 1), `bit reset_qreqn_high`(기본 1), `int unsigned exit_delay_cycles`(기본 0)
  - `class qch_monitor extends uvm_monitor;` — `uvm_analysis_port #(qch_monitor_item) ap`
  - `package qch_agent_pkg;`

- [ ] **Step 1: 실패하는 테스트를 먼저 작성**

`uvm/qch_monitor_test.sv` 를 아래 내용으로 생성한다.

```systemverilog
// ---------------------------------------------------------------------------
// qch_monitor_test
//
// qch_monitor 단위 테스트. driver 없이 테스트가 직접 인터페이스 신호를 흔들고,
// monitor 가 IHI0068D Table 2-1 대로 상태를 복원해 발행하는지 확인한다.
// ---------------------------------------------------------------------------
`include "uvm_macros.svh"
import uvm_pkg::*;
import qch_item_pkg::*;
import qch_agent_pkg::*;

class qch_monitor_test extends uvm_test;
  `uvm_component_utils(qch_monitor_test)

  uvm_analysis_imp #(qch_monitor_item, qch_monitor_test) mon_imp;
  qch_monitor_item collected[$];

  qch_monitor      mon;
  virtual qch_if   vif;

  function new(string name = "qch_monitor_test", uvm_component parent = null);
    super.new(name, parent);
    mon_imp = new("mon_imp", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual qch_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "virtual interface 'vif' not set")
    mon = qch_monitor::type_id::create("mon", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mon.ap.connect(mon_imp);
  endfunction

  virtual function void write(qch_monitor_item t);
    collected.push_back(t);
  endfunction

  // 신호를 한 번에 세팅하고 n 사이클 유지한다.
  // negedge 에서 구동하는 이유: monitor 는 posedge 에서 샘플링하므로, posedge 에
  // 값을 바꾸면 그 사이클에 새 값이 보이는지 옛 값이 보이는지 모호해진다.
  // negedge 에 구동하면 이어지는 n 개의 posedge 가 정확히 새 값을 본다.
  task drive_signals(bit qreqn, bit qacceptn, bit qdeny, bit qactive, int n = 1);
    @(negedge vif.clk);
    vif.QREQn    <= qreqn;
    vif.QACCEPTn <= qacceptn;
    vif.QDENY    <= qdeny;
    vif.QACTIVE  <= qactive;
    repeat (n) @(posedge vif.clk);
  endtask

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // 리셋 구간: monitor 는 아무것도 발행하면 안 된다.
    //
    // 여기서 이미 Q_RUN 값을 실어두는 것이 중요하다. monitor 는 리셋 해제 후
    // 첫 샘플을 "초기 상태" 로 잡고 발행하지 않는데, 그 시점에 다른 값이 실려
    // 있으면 초기 상태가 그 값이 되고, 이후 Q_RUN 으로 바뀌는 순간 의도하지 않은
    // 전이가 하나 더 발행되어 아래 기대 목록과 어긋난다.
    drive_signals(1'b1, 1'b1, 1'b0, 1'b0, 5);

    wait (vif.rst_n === 1'b1);

    // Q_RUN 에서 시작 (첫 샘플은 초기 상태로 잡히고 발행되지 않는다)
    drive_signals(1'b1, 1'b1, 1'b0, 1'b0, 3);

    // accept 경로: Q_RUN -> Q_REQUEST -> Q_STOPPED -> Q_EXIT -> Q_RUN
    drive_signals(1'b0, 1'b1, 1'b0, 1'b0, 4);  // Q_REQUEST, 4 사이클 체류
    drive_signals(1'b0, 1'b0, 1'b0, 1'b0, 2);  // Q_STOPPED
    drive_signals(1'b1, 1'b0, 1'b0, 1'b1, 2);  // Q_EXIT, QACTIVE HIGH
    drive_signals(1'b1, 1'b1, 1'b0, 1'b0, 2);  // Q_RUN

    // deny 경로: Q_RUN -> Q_REQUEST -> Q_DENIED -> Q_CONTINUE -> Q_RUN
    drive_signals(1'b0, 1'b1, 1'b0, 1'b0, 1);  // Q_REQUEST
    drive_signals(1'b0, 1'b1, 1'b1, 1'b0, 1);  // Q_DENIED
    drive_signals(1'b1, 1'b1, 1'b1, 1'b0, 1);  // Q_CONTINUE
    drive_signals(1'b1, 1'b1, 1'b0, 1'b0, 2);  // Q_RUN

    // illegal 조합: QACCEPTn LOW + QDENY HIGH
    drive_signals(1'b1, 1'b0, 1'b1, 1'b0, 2);  // QCH_ST_ILLEGAL
    drive_signals(1'b1, 1'b1, 1'b0, 1'b0, 2);  // Q_RUN 복귀

    check_results();

    phase.drop_objection(this);
  endtask

  task check_results();
    qch_state_e exp_states[$];
    exp_states = '{ QCH_ST_REQUEST, QCH_ST_STOPPED, QCH_ST_EXIT, QCH_ST_RUN,
                    QCH_ST_REQUEST, QCH_ST_DENIED, QCH_ST_CONTINUE, QCH_ST_RUN,
                    QCH_ST_ILLEGAL, QCH_ST_RUN };

    if (collected.size() != exp_states.size()) begin
      `uvm_error("MON", $sformatf("expected %0d transitions, got %0d",
                                  exp_states.size(), collected.size()))
      foreach (collected[i])
        `uvm_info("MON", $sformatf("  [%0d] %s -> %s (%0d cycles)", i,
                  collected[i].prev_state.name(), collected[i].state.name(),
                  collected[i].cycles_in_prev), UVM_LOW)
      return;
    end

    foreach (exp_states[i])
      if (collected[i].state != exp_states[i])
        `uvm_error("MON", $sformatf("transition %0d: expected %s, got %s",
                   i, exp_states[i].name(), collected[i].state.name()))

    // prev_state 가 직전 항목의 state 와 이어져야 한다
    for (int i = 1; i < collected.size(); i++)
      if (collected[i].prev_state != collected[i-1].state)
        `uvm_error("MON", $sformatf(
          "transition %0d: prev_state=%s does not match previous state=%s",
          i, collected[i].prev_state.name(), collected[i-1].state.name()))

    // Q_REQUEST 에 4 사이클 머물렀으므로 다음 전이의 cycles_in_prev 가 4 여야 한다
    if (collected[1].cycles_in_prev != 4)
      `uvm_error("MON", $sformatf(
        "cycles_in_prev for Q_REQUEST: expected 4, got %0d",
        collected[1].cycles_in_prev))

    // qactive 는 전이가 관측된 시점의 값이다. Q_EXIT 구간을 QACTIVE HIGH 로
    // 구동했으므로, Q_EXIT 로 "들어가는" 전이(collected[2] = STOPPED -> EXIT)에서
    // 1 이어야 한다. Q_EXIT 에서 "나가는" 전이(collected[3] = EXIT -> RUN)는 이미
    // Q_RUN 값(QACTIVE LOW)이 실린 뒤라 0 이다.
    if (collected[2].qactive !== 1'b1)
      `uvm_error("MON", "qactive should be 1 on the Q_STOPPED -> Q_EXIT transition")
    if (collected[3].qactive !== 1'b0)
      `uvm_error("MON", "qactive should be 0 on the Q_EXIT -> Q_RUN transition")
  endtask

endclass

// ---------------------------------------------------------------------------
// 시뮬레이션 entry point
// ---------------------------------------------------------------------------
module qch_mon_tb_top;

  logic clk   = 1'b0;
  logic rst_n = 1'b0;

  always #5ns clk = ~clk;

  qch_if u_if (.clk(clk), .rst_n(rst_n));

  initial begin
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual qch_if)::set(null, "*", "vif", u_if);
    run_test("qch_monitor_test");
  end

endmodule
```

- [ ] **Step 2: 테스트를 실행해서 실패를 확인**

Run:
```bash
vcs -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps uvm/qch_monitor_test.sv -o simv_qchmon
```

Expected: **컴파일 FAIL.** `qch_if`, `qch_agent_pkg`, `qch_monitor`, `qch_monitor_item`이 아직 없으므로 "Unable to find package"/"not declared" 류 에러가 난다.

시뮬레이터가 없으면 실행 불가임을 보고서에 적는다.

- [ ] **Step 3: 인터페이스 작성**

`uvm/qch_if.sv` 를 아래 내용으로 생성한다.

```systemverilog
// ---------------------------------------------------------------------------
// qch_if
//
// AMBA Low Power Interface(IHI0068D) Q-Channel 인터페이스.
//
// modport 로 신호 소유권을 나눈다. Controller 는 QREQn 만, Device 는
// QACCEPTn/QDENY/QACTIVE 만 구동한다. 반대편 신호를 실수로 구동하는 것을
// 컴파일 단계에서 막기 위해서다.
//
// 이 증분은 4 개 신호가 모두 존재한다고 가정한다. IHI0068D 2.1.4 가 허용하는
// QDENY/QACTIVE 생략 구성은 필요해지면 따로 다룬다.
// ---------------------------------------------------------------------------
`ifndef QCH_IF_SV
`define QCH_IF_SV

interface qch_if (input logic clk, input logic rst_n);

  logic QREQn;     // Controller -> Device : quiescence 요청 (active-LOW)
  logic QACCEPTn;  // Device -> Controller : 수락 (active-LOW)
  logic QDENY;     // Device -> Controller : 거부 (active-HIGH)
  logic QACTIVE;   // Device -> Controller : 할 일이 있음 (handshake 와 독립)

  modport controller (
    output QREQn,
    input  QACCEPTn, QDENY, QACTIVE,
    input  clk, rst_n
  );

  modport device (
    input  QREQn,
    output QACCEPTn, QDENY, QACTIVE,
    input  clk, rst_n
  );

  modport monitor (
    input QREQn, QACCEPTn, QDENY, QACTIVE,
    input clk, rst_n
  );

endinterface

`endif // QCH_IF_SV
```

- [ ] **Step 4: 상태 표현을 qch_items.sv 에 추가**

`uvm/qch_items.sv` 에서 `qch_active_action_e` typedef 블록 바로 다음에 아래를 추가한다.

```systemverilog
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
```

그리고 같은 파일의 `qch_device_active_item` 클래스 `endclass` 다음, `endpackage` 앞에 아래 클래스를 추가한다.

```systemverilog
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
```

- [ ] **Step 5: config 작성**

`uvm/qch_config.svh` 를 아래 내용으로 생성한다.

```systemverilog
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
```

- [ ] **Step 6: monitor 작성**

`uvm/qch_monitor.svh` 를 아래 내용으로 생성한다.

```systemverilog
// ---------------------------------------------------------------------------
// qch_monitor
//
// 4 개 신호를 매 클럭 샘플링해서 상태를 복원하고, 상태가 바뀔 때마다
// qch_monitor_item 을 발행한다. 역할과 무관하게 항상 만들어진다.
//
// 이 monitor 는 어떤 프로토콜 위반도 보고하지 않는다. QCH_ST_ILLEGAL 에
// 진입해도 그 상태를 발행할 뿐 uvm_error 를 내지 않는다. 검사는 별도 SVA
// 증분이 담당하며, 여기서 중복하면 이중 관리 대상이 된다.
// ---------------------------------------------------------------------------
class qch_monitor extends uvm_monitor;

  `uvm_component_utils(qch_monitor)

  virtual qch_if.monitor vif;

  uvm_analysis_port #(qch_monitor_item) ap;

  local qch_state_e  cur_state;
  local int unsigned cycles_in_cur;
  local bit          tracking;  // 리셋 해제 후 초기 상태를 잡았는가

  function new(string name = "qch_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    virtual qch_if raw_vif;
    super.build_phase(phase);
    if (!uvm_config_db#(virtual qch_if)::get(this, "", "vif", raw_vif))
      `uvm_fatal(get_type_name(), "virtual interface 'vif' not set in config_db")
    vif = raw_vif;
  endfunction

  virtual task run_phase(uvm_phase phase);
    qch_state_e      sampled;
    qch_monitor_item it;

    tracking      = 1'b0;
    cycles_in_cur = 0;

    forever begin
      @(posedge vif.clk);

      // 리셋 중에는 상태를 추적하지 않는다.
      if (vif.rst_n !== 1'b1) begin
        tracking      = 1'b0;
        cycles_in_cur = 0;
        continue;
      end

      sampled = qch_decode_state(vif.QREQn, vif.QACCEPTn, vif.QDENY);

      // 리셋 해제 후 첫 샘플은 초기 상태로만 잡고 발행하지 않는다.
      if (!tracking) begin
        cur_state     = sampled;
        cycles_in_cur = 1;
        tracking      = 1'b1;
        continue;
      end

      if (sampled == cur_state) begin
        cycles_in_cur++;
      end
      else begin
        it                = qch_monitor_item::type_id::create("mon_it");
        it.prev_state     = cur_state;
        it.state          = sampled;
        it.qactive        = vif.QACTIVE;
        it.cycles_in_prev = cycles_in_cur;
        ap.write(it);

        cur_state     = sampled;
        cycles_in_cur = 1;
      end
    end
  endtask

endclass
```

- [ ] **Step 7: 패키지 작성**

`uvm/qch_agent_pkg.sv` 를 아래 내용으로 생성한다.

```systemverilog
// ---------------------------------------------------------------------------
// qch_agent_pkg
//
// Q-Channel VIP 의 컴포넌트들. 자극 아이템 정의는 qch_item_pkg 에 있다.
//
// 컴파일 순서: qch_if.sv -> qch_items.sv -> qch_agent_pkg.sv
// ---------------------------------------------------------------------------
package qch_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import qch_item_pkg::*;

  `include "qch_config.svh"
  `include "qch_monitor.svh"

endpackage
```

- [ ] **Step 8: 테스트를 실행해서 통과를 확인**

Run:
```bash
vcs -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps +incdir+uvm \
    uvm/qch_if.sv uvm/qch_items.sv uvm/qch_agent_pkg.sv uvm/qch_monitor_test.sv \
    -o simv_qchmon
```
그다음:
```bash
./simv_qchmon +UVM_TESTNAME=qch_monitor_test
```

Expected: 컴파일 성공, 실행 후 `UVM_ERROR : 0` 및 `UVM_FATAL : 0`.

시뮬레이터가 없어 실행하지 못했다면 보고서에 그렇게 적는다.

- [ ] **Step 9: 커밋**

```bash
git add uvm/qch_if.sv uvm/qch_items.sv uvm/qch_config.svh uvm/qch_monitor.svh uvm/qch_agent_pkg.sv uvm/qch_monitor_test.sv
git commit -m "Add Q-Channel VIP interface, state decoding, and monitor"
```

---

### Task 2: sequencer + controller driver + agent

**Files:**
- Create: `uvm/qch_sequencers.svh`
- Create: `uvm/qch_controller_driver.svh`
- Create: `uvm/qch_agent.svh`
- Modify: `uvm/qch_agent_pkg.sv` (include 추가)
- Create: `uvm/qch_controller_test.sv`

**Interfaces:**
- Consumes: Task 1이 만든 `qch_if`(modport `controller`), `qch_config`, `qch_monitor`, `qch_monitor_item`, `qch_state_e`, `package qch_agent_pkg`. 기존 `qch_item_pkg`의 `qch_controller_item`(필드 `action`, `pre_delay_cycles`, `response_timeout_cycles`, `observed_response`, `response_latency_cycles`)
- Produces:
  - `typedef uvm_sequencer #(qch_controller_item) qch_controller_sequencer;`
  - `typedef uvm_sequencer #(qch_device_response_item) qch_device_response_sequencer;`
  - `typedef uvm_sequencer #(qch_device_active_item) qch_device_active_sequencer;`
  - `class qch_controller_driver extends uvm_driver #(qch_controller_item);`
  - `class qch_agent extends uvm_agent;` — 이 Task에서 만드는 멤버는 `cfg`, `mon`, `ctrl_seqr`, `ctrl_drv`, `rsp_seqr`, `act_seqr` 6개다. `rsp_seqr`/`act_seqr` 는 DEVICE 역할 분기에서 **선언하고 생성까지** 한다. device driver 멤버(`dev_drv`)는 이 Task에 **없다** — Task 3이 선언과 생성을 함께 추가하므로, 여기서 미리 선언하면 Task 3에서 중복 선언이 되어 컴파일이 깨진다.

- [ ] **Step 1: 실패하는 테스트를 먼저 작성**

`uvm/qch_controller_test.sv` 를 아래 내용으로 생성한다.

```systemverilog
// ---------------------------------------------------------------------------
// qch_controller_test
//
// qch_controller_driver 단위 테스트. device 쪽은 실제 driver 대신 테스트가
// 직접 QACCEPTn/QDENY 를 흔들어 흉내낸다.
// ---------------------------------------------------------------------------
`include "uvm_macros.svh"
import uvm_pkg::*;
import qch_item_pkg::*;
import qch_agent_pkg::*;

// controller 자극 시퀀스: 요청 -> (device 응답) -> 운영 허용
class qch_ctrl_smoke_seq extends uvm_sequence #(qch_controller_item);
  `uvm_object_utils(qch_ctrl_smoke_seq)

  qch_controller_item sent[$];

  function new(string name = "qch_ctrl_smoke_seq");
    super.new(name);
  endfunction

  virtual task body();
    qch_controller_item req;

    // 1) quiescence 요청
    req = qch_controller_item::type_id::create("req0");
    start_item(req);
    if (!req.randomize() with { action == QCH_REQUEST_QUIESCENCE;
                                pre_delay_cycles == 2;
                                response_timeout_cycles == 100; })
      `uvm_error(get_type_name(), "randomize() failed on req0")
    finish_item(req);
    sent.push_back(req);

    // 2) 운영 허용
    req = qch_controller_item::type_id::create("req1");
    start_item(req);
    if (!req.randomize() with { action == QCH_ALLOW_RUN;
                                pre_delay_cycles == 0;
                                response_timeout_cycles == 100; })
      `uvm_error(get_type_name(), "randomize() failed on req1")
    finish_item(req);
    sent.push_back(req);
  endtask
endclass

class qch_controller_test extends uvm_test;
  `uvm_component_utils(qch_controller_test)

  uvm_analysis_imp #(qch_monitor_item, qch_controller_test) mon_imp;
  qch_monitor_item collected[$];

  qch_agent      agent;
  qch_config     cfg;
  virtual qch_if vif;

  function new(string name = "qch_controller_test", uvm_component parent = null);
    super.new(name, parent);
    mon_imp = new("mon_imp", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual qch_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "virtual interface 'vif' not set")

    cfg                  = qch_config::type_id::create("cfg");
    cfg.role             = QCH_ROLE_CONTROLLER;
    cfg.reset_qreqn_high = 1'b1;
    uvm_config_db#(qch_config)::set(this, "agent", "cfg", cfg);

    agent = qch_agent::type_id::create("agent", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.mon.ap.connect(mon_imp);
  endfunction

  virtual function void write(qch_monitor_item t);
    collected.push_back(t);
  endfunction

  // device 흉내: QREQn 이 내려오면 3 사이클 뒤 QACCEPTn 을 내리고,
  //              QREQn 이 올라오면 2 사이클 뒤 QACCEPTn 을 올린다.
  task fake_device();
    vif.QACCEPTn <= 1'b0;
    vif.QDENY    <= 1'b0;
    vif.QACTIVE  <= 1'b0;
    wait (vif.rst_n === 1'b1);

    // 리셋에서 QREQn HIGH 로 나왔으므로 Q_EXIT -> Q_RUN 으로 진행시킨다
    repeat (2) @(posedge vif.clk);
    vif.QACCEPTn <= 1'b1;

    forever begin
      @(negedge vif.QREQn);
      repeat (3) @(posedge vif.clk);
      vif.QACCEPTn <= 1'b0;

      @(posedge vif.QREQn);
      repeat (2) @(posedge vif.clk);
      vif.QACCEPTn <= 1'b1;
    end
  endtask

  virtual task run_phase(uvm_phase phase);
    qch_ctrl_smoke_seq seq;

    phase.raise_objection(this);

    fork
      fake_device();
    join_none

    wait (vif.rst_n === 1'b1);
    repeat (5) @(posedge vif.clk);

    seq = qch_ctrl_smoke_seq::type_id::create("seq");
    seq.start(agent.ctrl_seqr);

    repeat (20) @(posedge vif.clk);
    check_results(seq);

    phase.drop_objection(this);
  endtask

  task check_results(qch_ctrl_smoke_seq seq);
    qch_controller_item req0, req1;

    if (seq.sent.size() != 2) begin
      `uvm_error("CTRL", $sformatf("expected 2 sent items, got %0d", seq.sent.size()))
      return;
    end
    req0 = seq.sent[0];
    req1 = seq.sent[1];

    // 요청에 대해 accept 를 관측했어야 한다
    if (req0.observed_response != QCH_RSP_ACCEPTED)
      `uvm_error("CTRL", $sformatf(
        "req0 (REQUEST_QUIESCENCE): expected QCH_RSP_ACCEPTED, got %s",
        req0.observed_response.name()))

    // fake_device 가 3 사이클 뒤 응답하므로 latency 가 0 보다 커야 한다
    if (req0.response_latency_cycles == 0)
      `uvm_error("CTRL", "req0 response_latency_cycles should be greater than 0")

    // 운영 허용 요청도 완료되었어야 한다
    if (req1.observed_response != QCH_RSP_ACCEPTED)
      `uvm_error("CTRL", $sformatf(
        "req1 (ALLOW_RUN): expected QCH_RSP_ACCEPTED, got %s",
        req1.observed_response.name()))

    // monitor 가 Q_STOPPED 를 관측했어야 한다
    begin
      bit saw_stopped = 1'b0;
      foreach (collected[i])
        if (collected[i].state == QCH_ST_STOPPED) saw_stopped = 1'b1;
      if (!saw_stopped)
        `uvm_error("CTRL", "monitor never observed QCH_ST_STOPPED")
    end

    // illegal 상태는 나오면 안 된다
    foreach (collected[i])
      if (collected[i].state == QCH_ST_ILLEGAL)
        `uvm_error("CTRL", $sformatf("illegal state observed at transition %0d", i))
  endtask

endclass

// ---------------------------------------------------------------------------
// 시뮬레이션 entry point
// ---------------------------------------------------------------------------
module qch_ctrl_tb_top;

  logic clk   = 1'b0;
  logic rst_n = 1'b0;

  always #5ns clk = ~clk;

  qch_if u_if (.clk(clk), .rst_n(rst_n));

  initial begin
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual qch_if)::set(null, "*", "vif", u_if);
    run_test("qch_controller_test");
  end

endmodule
```

- [ ] **Step 2: 테스트를 실행해서 실패를 확인**

Run:
```bash
vcs -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
    uvm/qch_if.sv uvm/qch_items.sv uvm/qch_agent_pkg.sv uvm/qch_controller_test.sv \
    -o simv_qchctrl
```

Expected: **컴파일 FAIL.** `qch_agent`, `qch_controller_sequencer`가 아직 없으므로 "not declared" 류 에러가 난다.

시뮬레이터가 없으면 실행 불가임을 보고서에 적는다.

- [ ] **Step 3: sequencer typedef 작성**

`uvm/qch_sequencers.svh` 를 아래 내용으로 생성한다.

```systemverilog
// ---------------------------------------------------------------------------
// sequencer 들
//
// Device 역할이 sequencer 를 두 개 쓰는 이유: 응답 루프는 QREQn 하강을 기다리며
// 오래 블록될 수 있는데, QACTIVE 아이템이 같은 sequencer 를 공유하면 그동안
// 막힌다. IHI0068D 2.1.1 이 보장하는 "QACTIVE 는 handshake 와 무관하게 아무 때나
// 구동 가능" 이라는 성질이 깨진다.
// ---------------------------------------------------------------------------

typedef uvm_sequencer #(qch_controller_item)      qch_controller_sequencer;
typedef uvm_sequencer #(qch_device_response_item) qch_device_response_sequencer;
typedef uvm_sequencer #(qch_device_active_item)   qch_device_active_sequencer;
```

- [ ] **Step 4: controller driver 작성**

`uvm/qch_controller_driver.svh` 를 아래 내용으로 생성한다.

```systemverilog
// ---------------------------------------------------------------------------
// qch_controller_driver
//
// QREQn 만 구동한다.
//
// 이 증분은 트랜잭션 도중 리셋을 지원하지 않는다. 리셋 해제를 한 번 기다린 뒤
// 아이템 루프에 들어간다.
// ---------------------------------------------------------------------------
class qch_controller_driver extends uvm_driver #(qch_controller_item);

  `uvm_component_utils(qch_controller_driver)

  virtual qch_if.controller vif;
  qch_config                cfg;

  function new(string name = "qch_controller_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    virtual qch_if raw_vif;
    super.build_phase(phase);
    if (!uvm_config_db#(virtual qch_if)::get(this, "", "vif", raw_vif))
      `uvm_fatal(get_type_name(), "virtual interface 'vif' not set in config_db")
    vif = raw_vif;
    if (!uvm_config_db#(qch_config)::get(this, "", "cfg", cfg))
      `uvm_fatal(get_type_name(), "qch_config 'cfg' not set in config_db")
  endfunction

  virtual task run_phase(uvm_phase phase);
    qch_controller_item req;

    // IHI0068D 2.1.2: controller 는 리셋 해제 시점의 QREQn 을 LOW(Q_STOPPED) 또는
    // HIGH(Q_EXIT) 중 하나로 고를 수 있다. 둘 다 합법이므로 config 로 받는다.
    vif.QREQn <= cfg.reset_qreqn_high;

    wait (vif.rst_n === 1'b1);
    @(posedge vif.clk);

    forever begin
      seq_item_port.get_next_item(req);
      drive_one(req);
      seq_item_port.item_done();
    end
  endtask

  local task drive_one(qch_controller_item req);
    int unsigned elapsed;
    bit          done;

    repeat (req.pre_delay_cycles) @(posedge vif.clk);

    vif.QREQn <= (req.action == QCH_REQUEST_QUIESCENCE) ? 1'b0 : 1'b1;
    @(posedge vif.clk);

    elapsed               = 0;
    done                  = 1'b0;
    req.observed_response = QCH_RSP_NONE;

    // 스펙은 device 응답 시간의 상한을 정의하지 않는다. timeout 은 무한 대기를
    // 피하려는 시험 편의상의 장치이며, timeout 자체는 프로토콜 위반이 아니므로
    // uvm_error 를 내지 않는다. 위반 판정은 SVA 몫이다.
    while (!done && elapsed < req.response_timeout_cycles) begin
      if (req.action == QCH_REQUEST_QUIESCENCE) begin
        if (vif.QACCEPTn === 1'b0) begin
          req.observed_response = QCH_RSP_ACCEPTED;
          done                  = 1'b1;
        end
        else if (vif.QDENY === 1'b1) begin
          req.observed_response = QCH_RSP_DENIED;
          done                  = 1'b1;
        end
      end
      else begin
        // ALLOW_RUN 은 Q_RUN 도달을 기다린다.
        // 이 결과에 QCH_RSP_ACCEPTED 를 재사용하는 것은 정확한 표현이 아니다.
        // action 필드와 같이 봐야 의미가 확정된다. enum 확장은 소비자(커버리지/
        // 스코어보드)가 생길 때 함께 한다.
        if (vif.QACCEPTn === 1'b1 && vif.QDENY === 1'b0) begin
          req.observed_response = QCH_RSP_ACCEPTED;
          done                  = 1'b1;
        end
      end

      if (!done) begin
        @(posedge vif.clk);
        elapsed++;
      end
    end

    if (!done) req.observed_response = QCH_RSP_TIMEOUT;
    req.response_latency_cycles = elapsed;
  endtask

endclass
```

- [ ] **Step 5: agent 작성**

`uvm/qch_agent.svh` 를 아래 내용으로 생성한다.

```systemverilog
// ---------------------------------------------------------------------------
// qch_agent
//
// config 의 role 을 보고 필요한 것만 만든다.
//
//   role                 monitor  sequencer                 driver
//   QCH_ROLE_CONTROLLER  O        1개 (controller)          controller driver
//   QCH_ROLE_DEVICE      O        2개 (response, active)    device driver
//   QCH_ROLE_PASSIVE     O        X                         X
//
// monitor 는 세 경우 모두 만든다. 관찰은 항상 필요하다.
// ---------------------------------------------------------------------------
class qch_agent extends uvm_agent;

  `uvm_component_utils(qch_agent)

  qch_config                    cfg;

  qch_monitor                   mon;

  qch_controller_sequencer      ctrl_seqr;
  qch_controller_driver         ctrl_drv;

  qch_device_response_sequencer rsp_seqr;
  qch_device_active_sequencer   act_seqr;

  function new(string name = "qch_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(qch_config)::get(this, "", "cfg", cfg))
      `uvm_fatal(get_type_name(), "qch_config 'cfg' not set in config_db")

    // 하위 컴포넌트도 cfg 를 볼 수 있게 한다
    uvm_config_db#(qch_config)::set(this, "*", "cfg", cfg);

    mon = qch_monitor::type_id::create("mon", this);

    case (cfg.role)
      QCH_ROLE_CONTROLLER: begin
        ctrl_seqr = qch_controller_sequencer::type_id::create("ctrl_seqr", this);
        ctrl_drv  = qch_controller_driver::type_id::create("ctrl_drv", this);
      end
      QCH_ROLE_DEVICE: begin
        // 이 Task 에서는 sequencer 만 만든다. device driver 와 그 연결, 응답
        // 시퀀스 기동은 다음 Task 에서 채운다.
        rsp_seqr = qch_device_response_sequencer::type_id::create("rsp_seqr", this);
        act_seqr = qch_device_active_sequencer::type_id::create("act_seqr", this);
      end
      QCH_ROLE_PASSIVE: begin
        // monitor 만 만든다
      end
    endcase
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.role == QCH_ROLE_CONTROLLER)
      ctrl_drv.seq_item_port.connect(ctrl_seqr.seq_item_export);
  endfunction

endclass
```

- [ ] **Step 6: 패키지에 include 추가**

`uvm/qch_agent_pkg.sv` 에서 `` `include "qch_monitor.svh" `` 다음 줄부터 아래를 추가한다.

```systemverilog
  `include "qch_sequencers.svh"
  `include "qch_controller_driver.svh"
  `include "qch_agent.svh"
```

- [ ] **Step 7: 테스트를 실행해서 통과를 확인**

Run:
```bash
vcs -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
    uvm/qch_if.sv uvm/qch_items.sv uvm/qch_agent_pkg.sv uvm/qch_controller_test.sv \
    -o simv_qchctrl
```
그다음:
```bash
./simv_qchctrl +UVM_TESTNAME=qch_controller_test
```

Expected: 컴파일 성공, `UVM_ERROR : 0` 및 `UVM_FATAL : 0`.

시뮬레이터가 없어 실행하지 못했다면 보고서에 그렇게 적는다.

- [ ] **Step 8: 커밋**

```bash
git add uvm/qch_sequencers.svh uvm/qch_controller_driver.svh uvm/qch_agent.svh uvm/qch_agent_pkg.sv uvm/qch_controller_test.sv
git commit -m "Add Q-Channel VIP sequencers, controller driver, and agent"
```

---

### Task 3: device driver + responder 시퀀스 + 루프백 테스트

**Files:**
- Create: `uvm/qch_device_driver.svh`
- Create: `uvm/qch_responder_seq.svh`
- Modify: `uvm/qch_agent.svh` (DEVICE 역할에 driver 생성/연결/시퀀스 기동 추가)
- Modify: `uvm/qch_agent_pkg.sv` (include 추가)
- Create: `uvm/qch_loopback_test.sv`

**Interfaces:**
- Consumes: Task 1·2가 만든 `qch_if`(modport `device`), `qch_config`, `qch_monitor`, `qch_monitor_item`, `qch_state_e`, `qch_agent`, `qch_device_response_sequencer`, `qch_device_active_sequencer`. 기존 `qch_item_pkg`의 `qch_device_response_item`(필드 `policy`, `response_delay_cycles`)과 `qch_device_active_item`(필드 `action`, `pre_delay_cycles`)
- Produces:
  - `class qch_device_driver extends uvm_driver #(qch_device_response_item);` — 추가 포트 `uvm_seq_item_pull_port #(qch_device_active_item) act_seq_item_port;`
  - `class qch_responder_seq extends uvm_sequence #(qch_device_response_item);`
  - `qch_agent`에 멤버 `qch_device_driver dev_drv;` 추가

- [ ] **Step 1: 실패하는 테스트를 먼저 작성**

`uvm/qch_loopback_test.sv` 를 아래 내용으로 생성한다.

```systemverilog
// ---------------------------------------------------------------------------
// qch_loopback_test
//
// DUT 없이 VIP 끼리 마주보게 연결한다.
//
//   [qch_agent : CONTROLLER] ---- qch_if ---- [qch_agent : DEVICE]
//                                   |
//                            [qch_agent : PASSIVE]  (관찰)
//
// 세 agent 가 같은 인터페이스를 공유하되, 구동하는 신호가 modport 로 갈려 있어
// 충돌하지 않는다.
// ---------------------------------------------------------------------------
`include "uvm_macros.svh"
import uvm_pkg::*;
import qch_item_pkg::*;
import qch_agent_pkg::*;

// controller 자극: quiescence 요청과 운영 허용을 번갈아 반복한다
class qch_loopback_seq extends uvm_sequence #(qch_controller_item);
  `uvm_object_utils(qch_loopback_seq)

  int unsigned n_rounds = 20;

  function new(string name = "qch_loopback_seq");
    super.new(name);
  endfunction

  virtual task body();
    qch_controller_item req;

    repeat (n_rounds) begin
      req = qch_controller_item::type_id::create("req_q");
      start_item(req);
      if (!req.randomize() with { action == QCH_REQUEST_QUIESCENCE;
                                  pre_delay_cycles inside {[0:5]};
                                  response_timeout_cycles == 200; })
        `uvm_error(get_type_name(), "randomize() failed on quiescence request")
      finish_item(req);

      req = qch_controller_item::type_id::create("req_r");
      start_item(req);
      if (!req.randomize() with { action == QCH_ALLOW_RUN;
                                  pre_delay_cycles inside {[0:5]};
                                  response_timeout_cycles == 200; })
        `uvm_error(get_type_name(), "randomize() failed on allow-run request")
      finish_item(req);
    end
  endtask
endclass

class qch_loopback_test extends uvm_test;
  `uvm_component_utils(qch_loopback_test)

  uvm_analysis_imp #(qch_monitor_item, qch_loopback_test) mon_imp;
  qch_monitor_item collected[$];

  qch_agent      ctrl_agent, dev_agent, mon_agent;
  qch_config     ctrl_cfg,   dev_cfg,   mon_cfg;
  virtual qch_if vif;

  function new(string name = "qch_loopback_test", uvm_component parent = null);
    super.new(name, parent);
    mon_imp = new("mon_imp", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual qch_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "virtual interface 'vif' not set")

    ctrl_cfg                  = qch_config::type_id::create("ctrl_cfg");
    ctrl_cfg.role             = QCH_ROLE_CONTROLLER;
    ctrl_cfg.reset_qreqn_high = 1'b1;
    uvm_config_db#(qch_config)::set(this, "ctrl_agent", "cfg", ctrl_cfg);

    dev_cfg                     = qch_config::type_id::create("dev_cfg");
    dev_cfg.role                = QCH_ROLE_DEVICE;
    dev_cfg.start_responder_seq = 1'b1;
    dev_cfg.exit_delay_cycles   = 2;
    uvm_config_db#(qch_config)::set(this, "dev_agent", "cfg", dev_cfg);

    mon_cfg      = qch_config::type_id::create("mon_cfg");
    mon_cfg.role = QCH_ROLE_PASSIVE;
    uvm_config_db#(qch_config)::set(this, "mon_agent", "cfg", mon_cfg);

    ctrl_agent = qch_agent::type_id::create("ctrl_agent", this);
    dev_agent  = qch_agent::type_id::create("dev_agent",  this);
    mon_agent  = qch_agent::type_id::create("mon_agent",  this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mon_agent.mon.ap.connect(mon_imp);
  endfunction

  virtual function void write(qch_monitor_item t);
    collected.push_back(t);
  endfunction

  virtual task run_phase(uvm_phase phase);
    qch_loopback_seq seq;

    phase.raise_objection(this);

    // IHI0068D 2.1.2: 리셋 중 device 는 QACCEPTn 과 QDENY 를 둘 다 LOW 로 구동해야
    // 한다. 리셋이 풀리기 직전 값을 확인한다.
    wait (vif.rst_n === 1'b1);
    if (vif.QACCEPTn !== 1'b0)
      `uvm_error("LOOP", $sformatf(
        "at reset release QACCEPTn should be 0, got %b", vif.QACCEPTn))
    if (vif.QDENY !== 1'b0)
      `uvm_error("LOOP", $sformatf(
        "at reset release QDENY should be 0, got %b", vif.QDENY))
    if (vif.QREQn !== ctrl_cfg.reset_qreqn_high)
      `uvm_error("LOOP", $sformatf(
        "at reset release QREQn should be %b (cfg.reset_qreqn_high), got %b",
        ctrl_cfg.reset_qreqn_high, vif.QREQn))

    repeat (5) @(posedge vif.clk);

    seq          = qch_loopback_seq::type_id::create("seq");
    seq.n_rounds = 20;
    seq.start(ctrl_agent.ctrl_seqr);

    repeat (50) @(posedge vif.clk);
    check_results();

    phase.drop_objection(this);
  endtask

  task check_results();
    bit seen[qch_state_e];

    if (collected.size() == 0) begin
      `uvm_error("LOOP", "monitor observed no transitions at all")
      return;
    end

    foreach (collected[i]) begin
      seen[collected[i].state] = 1'b1;

      // 상태 전이가 끊기지 않고 이어져야 한다
      if (i > 0 && collected[i].prev_state != collected[i-1].state)
        `uvm_error("LOOP", $sformatf(
          "transition %0d: prev_state=%s does not match previous state=%s",
          i, collected[i].prev_state.name(), collected[i-1].state.name()))
    end

    // illegal 상태는 절대 나오면 안 된다
    if (seen.exists(QCH_ST_ILLEGAL))
      `uvm_error("LOOP", "QCH_ST_ILLEGAL was observed — driver drove an illegal combination")

    // accept 경로와 deny 경로를 모두 밟았어야 한다.
    // responder 시퀀스가 policy 를 50:50 으로 뽑으므로 20 라운드면 양쪽 다 나온다.
    if (!seen.exists(QCH_ST_STOPPED))
      `uvm_error("LOOP", "never reached QCH_ST_STOPPED (accept path untested)")
    if (!seen.exists(QCH_ST_DENIED))
      `uvm_error("LOOP", "never reached QCH_ST_DENIED (deny path untested)")
    if (!seen.exists(QCH_ST_CONTINUE))
      `uvm_error("LOOP", "never reached QCH_ST_CONTINUE")
    if (!seen.exists(QCH_ST_EXIT))
      `uvm_error("LOOP", "never reached QCH_ST_EXIT")
    if (!seen.exists(QCH_ST_REQUEST))
      `uvm_error("LOOP", "never reached QCH_ST_REQUEST")
    if (!seen.exists(QCH_ST_RUN))
      `uvm_error("LOOP", "never reached QCH_ST_RUN")

    `uvm_info("LOOP", $sformatf("observed %0d transitions", collected.size()), UVM_LOW)
  endtask

endclass

// ---------------------------------------------------------------------------
// qch_delay_test
//
// device 의 response_delay_cycles 가 실제 파형에 반영되는지 확인한다.
// responder 자동 기동을 끄고, 지연을 고정한 자체 시퀀스를 올린 뒤 monitor 가
// 관측한 Q_REQUEST 체류 시간을 본다.
//
// 정확한 사이클 수는 샘플링 오프셋 때문에 예측이 어려우므로 범위로 확인한다.
// 지연이 무시되면 체류가 1~2 사이클에 그치므로 아래 범위에서 걸린다.
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

class qch_delay_test extends uvm_test;
  `uvm_component_utils(qch_delay_test)

  uvm_analysis_imp #(qch_monitor_item, qch_delay_test) mon_imp;
  qch_monitor_item collected[$];

  qch_agent      ctrl_agent, dev_agent, mon_agent;
  qch_config     ctrl_cfg,   dev_cfg,   mon_cfg;
  virtual qch_if vif;

  localparam int unsigned FIXED_DELAY = 8;

  function new(string name = "qch_delay_test", uvm_component parent = null);
    super.new(name, parent);
    mon_imp = new("mon_imp", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual qch_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "virtual interface 'vif' not set")

    ctrl_cfg                  = qch_config::type_id::create("ctrl_cfg");
    ctrl_cfg.role             = QCH_ROLE_CONTROLLER;
    ctrl_cfg.reset_qreqn_high = 1'b1;
    uvm_config_db#(qch_config)::set(this, "ctrl_agent", "cfg", ctrl_cfg);

    dev_cfg                     = qch_config::type_id::create("dev_cfg");
    dev_cfg.role                = QCH_ROLE_DEVICE;
    dev_cfg.start_responder_seq = 1'b0;   // 자체 시퀀스를 올린다
    dev_cfg.exit_delay_cycles   = 0;
    uvm_config_db#(qch_config)::set(this, "dev_agent", "cfg", dev_cfg);

    mon_cfg      = qch_config::type_id::create("mon_cfg");
    mon_cfg.role = QCH_ROLE_PASSIVE;
    uvm_config_db#(qch_config)::set(this, "mon_agent", "cfg", mon_cfg);

    ctrl_agent = qch_agent::type_id::create("ctrl_agent", this);
    dev_agent  = qch_agent::type_id::create("dev_agent",  this);
    mon_agent  = qch_agent::type_id::create("mon_agent",  this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mon_agent.mon.ap.connect(mon_imp);
  endfunction

  virtual function void write(qch_monitor_item t);
    collected.push_back(t);
  endfunction

  virtual task run_phase(uvm_phase phase);
    qch_fixed_delay_seq dly_seq;
    qch_loopback_seq    ctrl_seq;

    phase.raise_objection(this);

    wait (vif.rst_n === 1'b1);
    repeat (5) @(posedge vif.clk);

    dly_seq             = qch_fixed_delay_seq::type_id::create("dly_seq");
    dly_seq.fixed_delay = FIXED_DELAY;
    fork
      dly_seq.start(dev_agent.rsp_seqr);
    join_none

    ctrl_seq          = qch_loopback_seq::type_id::create("ctrl_seq");
    ctrl_seq.n_rounds = 5;
    ctrl_seq.start(ctrl_agent.ctrl_seqr);

    repeat (30) @(posedge vif.clk);
    check_delay();

    phase.drop_objection(this);
  endtask

  task check_delay();
    int n_checked = 0;

    // Q_REQUEST -> Q_STOPPED 전이의 cycles_in_prev 가 Q_REQUEST 체류 시간이다.
    foreach (collected[i]) begin
      if (collected[i].prev_state == QCH_ST_REQUEST &&
          collected[i].state      == QCH_ST_STOPPED) begin
        n_checked++;
        // 정확한 사이클 수는 controller 의 QREQn 구동 엣지와 monitor 의 샘플링
        // 엣지 관계에 따라 1~2 사이클 흔들린다. 양쪽에 여유를 두되, 지연이 아예
        // 무시된 경우(체류 1~2 사이클)는 확실히 걸리도록 폭을 잡는다.
        if (collected[i].cycles_in_prev < FIXED_DELAY - 2 ||
            collected[i].cycles_in_prev > FIXED_DELAY + 3)
          `uvm_error("DLY", $sformatf(
            "Q_REQUEST dwell = %0d cycles, expected within [%0d:%0d] for response_delay_cycles=%0d",
            collected[i].cycles_in_prev, FIXED_DELAY - 2, FIXED_DELAY + 3, FIXED_DELAY))
      end
    end

    if (n_checked == 0)
      `uvm_error("DLY", "no Q_REQUEST -> Q_STOPPED transition was observed")
    else
      `uvm_info("DLY", $sformatf("checked %0d accept transitions", n_checked), UVM_LOW)
  endtask

endclass

// ---------------------------------------------------------------------------
// 시뮬레이션 entry point
// ---------------------------------------------------------------------------
module qch_loopback_tb_top;

  logic clk   = 1'b0;
  logic rst_n = 1'b0;

  always #5ns clk = ~clk;

  qch_if u_if (.clk(clk), .rst_n(rst_n));

  initial begin
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual qch_if)::set(null, "*", "vif", u_if);
    run_test("qch_loopback_test");
  end

endmodule
```

- [ ] **Step 2: 테스트를 실행해서 실패를 확인**

Run:
```bash
vcs -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
    uvm/qch_if.sv uvm/qch_items.sv uvm/qch_agent_pkg.sv uvm/qch_loopback_test.sv \
    -o simv_qchloop
```

Expected: **컴파일은 통과할 수 있으나 실행 시 FAIL.** DEVICE 역할 agent가 아직 driver를 만들지 않으므로 `QACCEPTn`/`QDENY`가 구동되지 않고, monitor가 전이를 거의 관측하지 못해 `never reached QCH_ST_STOPPED` 등의 에러가 난다.

시뮬레이터가 없으면 실행 불가임을 보고서에 적는다.

- [ ] **Step 3: device driver 작성**

`uvm/qch_device_driver.svh` 를 아래 내용으로 생성한다.

```systemverilog
// ---------------------------------------------------------------------------
// qch_device_driver
//
// QACCEPTn / QDENY / QACTIVE 를 구동한다.
//
// 세 프로세스가 독립적으로 돈다:
//   response_loop : QREQn 하강에 대해 아이템의 accept/deny 정책을 적용
//   exit_loop     : QREQn 이 HIGH 로 돌아오면 QACCEPTn 을 올리거나 QDENY 를 내림
//   active_loop   : QACTIVE 아이템을 처리 (handshake 와 무관)
//
// response_loop 와 active_loop 는 서로 다른 sequencer 에서 아이템을 받는다.
// 같은 sequencer 를 쓰면 응답 대기 중에 QACTIVE 가 막힌다.
//
// 이 증분은 트랜잭션 도중 리셋을 지원하지 않는다.
// ---------------------------------------------------------------------------
class qch_device_driver extends uvm_driver #(qch_device_response_item);

  `uvm_component_utils(qch_device_driver)

  // 기본 seq_item_port 는 응답 아이템용이고, QACTIVE 용 포트를 따로 둔다.
  uvm_seq_item_pull_port #(qch_device_active_item) act_seq_item_port;

  virtual qch_if.device vif;
  qch_config            cfg;

  function new(string name = "qch_device_driver", uvm_component parent = null);
    super.new(name, parent);
    act_seq_item_port = new("act_seq_item_port", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    virtual qch_if raw_vif;
    super.build_phase(phase);
    if (!uvm_config_db#(virtual qch_if)::get(this, "", "vif", raw_vif))
      `uvm_fatal(get_type_name(), "virtual interface 'vif' not set in config_db")
    vif = raw_vif;
    if (!uvm_config_db#(qch_config)::get(this, "", "cfg", cfg))
      `uvm_fatal(get_type_name(), "qch_config 'cfg' not set in config_db")
  endfunction

  virtual task run_phase(uvm_phase phase);
    // IHI0068D 2.1.2: "At reset assertion, a device must drive both QACCEPTn
    // and QDENY LOW." QACTIVE 는 LOW/HIGH 둘 다 허용되며, 시작 시 할 일이 없으면
    // LOW 가 권장된다.
    vif.QACCEPTn <= 1'b0;
    vif.QDENY    <= 1'b0;
    vif.QACTIVE  <= 1'b0;

    wait (vif.rst_n === 1'b1);
    @(posedge vif.clk);

    fork
      response_loop();
      exit_loop();
      active_loop();
    join
  endtask

  // QREQn 하강에 대한 응답. 아이템을 엣지 전에 미리 확보한다 — 엣지 후에
  // 시퀀스를 기다리면 response_delay_cycles 가 의미를 잃는다.
  //
  // qch_device_response_item 의 pre_delay_cycles 는 여기서 무시한다. 이 아이템은
  // 즉시 구동형이 아니라 QREQn 하강을 기다리는 반응형이라 "구동 전 대기" 의
  // 기준점이 없다. 지연은 response_delay_cycles 하나만 쓴다.
  local task response_loop();
    qch_device_response_item req;

    forever begin
      seq_item_port.get_next_item(req);

      @(negedge vif.QREQn);

      repeat (req.response_delay_cycles) @(posedge vif.clk);

      if (req.policy == QCH_ACCEPT) vif.QACCEPTn <= 1'b0;
      else                          vif.QDENY    <= 1'b1;

      @(posedge vif.clk);
      seq_item_port.item_done();
    end
  endtask

  // QREQn 이 HIGH 인데 아직 Q_RUN 이 아니면 되돌린다.
  //   Q_EXIT     (QACCEPTn LOW) -> QACCEPTn 을 HIGH 로
  //   Q_CONTINUE (QDENY HIGH)   -> QDENY 를 LOW 로
  //
  // 이 두 엣지는 아이템 정책의 대상이 아니다. handshake rules 상 device 에게
  // 선택지가 없고, controller 가 QREQn 을 올린 뒤에만 가능하기 때문이다.
  // 따라서 타이밍만 config 로 준다.
  //
  // 리셋에서 QREQn HIGH 로 나온 경우(Q_EXIT)도 이 루프가 그대로 처리한다.
  local task exit_loop();
    forever begin
      @(posedge vif.clk);
      if (vif.QREQn === 1'b1 && (vif.QACCEPTn === 1'b0 || vif.QDENY === 1'b1)) begin
        repeat (cfg.exit_delay_cycles) @(posedge vif.clk);
        if (vif.QACCEPTn === 1'b0) vif.QACCEPTn <= 1'b1;
        if (vif.QDENY    === 1'b1) vif.QDENY    <= 1'b0;
      end
    end
  endtask

  // QACTIVE 는 handshake 와 완전히 독립이므로 별도 sequencer 에서 받는다.
  local task active_loop();
    qch_device_active_item req;

    forever begin
      act_seq_item_port.get_next_item(req);
      repeat (req.pre_delay_cycles) @(posedge vif.clk);
      vif.QACTIVE <= (req.action == QCH_ACTIVE_HIGH) ? 1'b1 : 1'b0;
      @(posedge vif.clk);
      act_seq_item_port.item_done();
    end
  endtask

endclass
```

- [ ] **Step 4: responder 시퀀스 작성**

`uvm/qch_responder_seq.svh` 를 아래 내용으로 생성한다.

```systemverilog
// ---------------------------------------------------------------------------
// qch_responder_seq
//
// Device 역할일 때 agent 가 자동으로 올리는 응답 전담 시퀀스.
//
// driver 가 아이템을 하나 소비할 때마다 다음 것이 새로 randomize 되므로, 매
// 요청마다 독립적으로 뽑힌 accept/deny 가 적용된다. qch_device_response_item 의
// 50:50 분포가 평상 테스트에서 실제로 살아나는 지점이 여기다.
//
// 특정 시나리오가 필요한 테스트는 config 의 start_responder_seq 를 0 으로 두고
// 자기 시퀀스를 직접 올린다.
// ---------------------------------------------------------------------------
class qch_responder_seq extends uvm_sequence #(qch_device_response_item);

  `uvm_object_utils(qch_responder_seq)

  function new(string name = "qch_responder_seq");
    super.new(name);
  endfunction

  virtual task body();
    qch_device_response_item req;

    forever begin
      req = qch_device_response_item::type_id::create("rsp_req");
      start_item(req);
      if (!req.randomize())
        `uvm_error(get_type_name(), "randomize() failed on qch_device_response_item")
      finish_item(req);
    end
  endtask

endclass
```

- [ ] **Step 5: agent 에 DEVICE 역할 채우기**

`uvm/qch_agent.svh` 에서 세 군데를 고친다.

첫째, 멤버 선언에서 `qch_device_active_sequencer   act_seqr;` 다음 줄에 추가한다.

```systemverilog
  qch_device_driver             dev_drv;
```

둘째, `build_phase` 의 `QCH_ROLE_DEVICE` 분기를 아래로 교체한다.

```systemverilog
      QCH_ROLE_DEVICE: begin
        rsp_seqr = qch_device_response_sequencer::type_id::create("rsp_seqr", this);
        act_seqr = qch_device_active_sequencer::type_id::create("act_seqr", this);
        dev_drv  = qch_device_driver::type_id::create("dev_drv", this);
      end
```

셋째, `connect_phase` 의 `endfunction` 앞에 추가한다.

```systemverilog
    if (cfg.role == QCH_ROLE_DEVICE) begin
      dev_drv.seq_item_port.connect(rsp_seqr.seq_item_export);
      dev_drv.act_seq_item_port.connect(act_seqr.seq_item_export);
    end
```

넷째, `connect_phase` 의 `endfunction` 다음, 클래스의 `endclass` 앞에 `run_phase` 를 추가한다.

```systemverilog
  // DEVICE 역할이면 응답 전담 시퀀스를 자동으로 올린다.
  // 이 시퀀스는 무한 루프이므로 objection 을 걸지 않는다. 걸면 테스트가 끝나지 않는다.
  virtual task run_phase(uvm_phase phase);
    qch_responder_seq rsp_seq;
    if (cfg.role == QCH_ROLE_DEVICE && cfg.start_responder_seq) begin
      rsp_seq = qch_responder_seq::type_id::create("rsp_seq");
      rsp_seq.start(rsp_seqr);
    end
  endtask
```

- [ ] **Step 6: 패키지에 include 추가**

`uvm/qch_agent_pkg.sv` 에서 `` `include "qch_controller_driver.svh" `` 다음 줄에 아래 두 줄을 추가한다. (`qch_agent.svh` 는 이들을 참조하므로 반드시 그 앞에 와야 한다)

```systemverilog
  `include "qch_device_driver.svh"
  `include "qch_responder_seq.svh"
```

- [ ] **Step 7: 테스트를 실행해서 통과를 확인**

Run:
```bash
vcs -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
    uvm/qch_if.sv uvm/qch_items.sv uvm/qch_agent_pkg.sv uvm/qch_loopback_test.sv \
    -o simv_qchloop
```
그다음:
```bash
./simv_qchloop +UVM_TESTNAME=qch_loopback_test
```

Expected: 컴파일 성공, `UVM_ERROR : 0` 및 `UVM_FATAL : 0`. 로그에 `observed N transitions` (N은 0보다 큰 수)가 찍힌다.

이어서 지연 정확도 테스트도 같은 실행파일로 돌린다:
```bash
./simv_qchloop +UVM_TESTNAME=qch_delay_test
```

Expected: `UVM_ERROR : 0` 및 `UVM_FATAL : 0`. 로그에 `checked N accept transitions` (N은 0보다 큰 수)가 찍힌다.

시뮬레이터가 없어 실행하지 못했다면 보고서에 그렇게 적는다.

- [ ] **Step 8: 커밋**

```bash
git add uvm/qch_device_driver.svh uvm/qch_responder_seq.svh uvm/qch_agent.svh uvm/qch_agent_pkg.sv uvm/qch_loopback_test.sv
git commit -m "Add Q-Channel VIP device driver and loopback test"
```
