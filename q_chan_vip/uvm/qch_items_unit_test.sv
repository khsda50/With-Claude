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

  // -------------------------------------------------------------------
  // qch_device_response_item:
  //  - policy 가 ACCEPT/DENY 로 고르게 나와야 한다.
  //    "한 번이라도 나왔는가" 로는 분포가 망가진 것을 잡지 못하므로 개수를 센다.
  //  - response_delay_cycles 는 soft 범위 [0:20] 안이어야 한다
  //  - 지연은 두 정책 모두에 적용되므로 DENY + 비0 지연도 만들 수 있어야 한다
  // -------------------------------------------------------------------
  task check_device_response_item();
    qch_device_response_item it;
    int n_accept, n_deny;

    n_accept = 0;
    n_deny   = 0;

    it = qch_device_response_item::type_id::create("dev_rsp_it");

    repeat (N_TRIES) begin
      if (!it.randomize()) begin
        `uvm_error("DEVRSP", "randomize() failed on qch_device_response_item")
      end
      else begin
        if (it.policy == QCH_ACCEPT) n_accept++;
        if (it.policy == QCH_DENY)   n_deny++;

        if (it.response_delay_cycles > 20)
          `uvm_error("DEVRSP", $sformatf(
            "response_delay_cycles=%0d is outside soft range [0:20]",
            it.response_delay_cycles))
      end
    end

    // 기대 분포는 50:50. N_TRIES=100 에서 표준편차가 5 이므로 [20:80] 범위는
    // 정상 분포에서는 사실상 걸리지 않고, 심하게 치우친 경우만 잡는다.
    if (n_deny < 20 || n_deny > 80)
      `uvm_error("DEVRSP", $sformatf(
        "policy distribution is skewed: QCH_DENY %0d / QCH_ACCEPT %0d out of %0d",
        n_deny, n_accept, N_TRIES))

    // 두 정책 모두 지연을 지정할 수 있어야 한다
    if (!it.randomize() with { policy == QCH_ACCEPT; response_delay_cycles == 7; })
      `uvm_error("DEVRSP", "could not constrain policy=QCH_ACCEPT with response_delay_cycles=7")
    else if (it.policy != QCH_ACCEPT || it.response_delay_cycles != 7)
      `uvm_error("DEVRSP", "ACCEPT policy/delay constraint did not take effect")

    if (!it.randomize() with { policy == QCH_DENY; response_delay_cycles == 5; })
      `uvm_error("DEVRSP", "could not constrain policy=QCH_DENY with response_delay_cycles=5")
    else if (it.policy != QCH_DENY || it.response_delay_cycles != 5)
      `uvm_error("DEVRSP", "DENY policy/delay constraint did not take effect")
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

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "=== qch item unit test start ===", UVM_LOW)

    check_base_item();
    check_controller_item();
    check_device_response_item();
    check_device_active_item();

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
