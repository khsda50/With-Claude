// ---------------------------------------------------------------------------
// qch_env_example.sv
//
// 사내 환경에 붙일 때의 템플릿. 그대로 컴파일되는 것을 목표로 한 파일이 아니라,
// 세 군데(bind 문 / TB top 배선 / 테스트)를 어떻게 채우는지 보이는 파일이다.
// `QCH_EXAMPLE_TB` 를 정의하면 TB top 까지 컴파일된다.
//
// 붙이는 순서
//   1. DUT 의 Q-Channel 포트 이름을 찾는다
//   2. 아래 bind 문에서 신호 이름을 실제 이름으로 바꾼다
//   3. TB top 의 initial 블록에서 인터페이스 핸들을 config_db 로 넘긴다
//      (기존 TB 가 있으면 그쪽 run_test() 앞에 두 줄 추가하면 된다)
//   4. 테스트에서 env.ctrl_seqr 에 시퀀스를 올린다
//
// 역할 선택
//   CRMU 가 아직 없다 → VIP 를 CONTROLLER 로 세워 없는 CRMU 를 대신하고,
//                       실제 CPU 서브시스템의 device 인터페이스를 DUT 로 둔다
//   CPU 측이 없다     → VIP 를 DEVICE 로 세워 responder 를 대신한다
//   양쪽 다 있다      → PASSIVE 로 관측만 한다 (커버리지·체커 목적)
// ---------------------------------------------------------------------------
`include "uvm_macros.svh"
import uvm_pkg::*;
import qch_item_pkg::*;
import qch_agent_pkg::*;

// ---------------------------------------------------------------------------
// 테스트
//
// env 를 만들고 cfg 를 대입하는 것 외에 배선이 없다. sequencer 는 env 가
// connect_phase 에서 올려주므로 run_phase 에서 바로 쓴다.
// ---------------------------------------------------------------------------
class qch_env_example_test extends uvm_test;
  `uvm_component_utils(qch_env_example_test)

  qch_config cfg_ctrl;
  qch_env    env_ctrl;

  // 채널이 하나면 아래 두 줄은 지운다.
  qch_config cfg_dev;
  qch_env    env_dev;

  function new(string name = "qch_env_example_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // --- 채널 1: VIP 가 controller (없는 CRMU 를 대신) ---------------------
    cfg_ctrl                  = qch_config::type_id::create("cfg_ctrl");
    cfg_ctrl.role             = QCH_ROLE_CONTROLLER;
    // 리셋 해제 시점의 QREQn. IHI0068D 2.1.2 는 HIGH(Q_EXIT)/LOW(Q_STOPPED) 둘 다
    // 허용한다. DUT 가 기대하는 쪽으로 맞춘다.
    cfg_ctrl.reset_qreqn_high = 1'b1;

    if (!uvm_config_db#(virtual qch_if)::get(this, "", "vif_ctrl", cfg_ctrl.vif))
      `uvm_fatal(get_type_name(), "\"vif_ctrl\" 가 config_db 에 없다 (TB top 확인)")

    env_ctrl     = qch_env::type_id::create("env_ctrl", this);
    // build_phase 는 top-down 이므로, 여기서 대입해도 env 의 build_phase 보다 앞이다.
    env_ctrl.cfg = cfg_ctrl;

    // --- 채널 2: VIP 가 device (없는 CPU 측 responder 를 대신) -------------
    cfg_dev                     = qch_config::type_id::create("cfg_dev");
    cfg_dev.role                = QCH_ROLE_DEVICE;
    // 1 이면 agent 가 qch_responder_seq 를 자동으로 올려 매 요청에 accept/deny 를
    // 무작위로 응답한다. 특정 시나리오를 직접 몰고 싶으면 0 으로 두고
    // env_dev.rsp_seqr 에 자기 시퀀스를 올린다.
    cfg_dev.start_responder_seq = 1'b1;
    cfg_dev.exit_delay_cycles   = 0;

    if (!uvm_config_db#(virtual qch_if)::get(this, "", "vif_dev", cfg_dev.vif))
      `uvm_fatal(get_type_name(), "\"vif_dev\" 가 config_db 에 없다 (TB top 확인)")

    env_dev     = qch_env::type_id::create("env_dev", this);
    env_dev.cfg = cfg_dev;
  endfunction

  virtual task run_phase(uvm_phase phase);
    qch_quiesce_seq seq;

    phase.raise_objection(this);

    // DUT 리셋 해제를 기다린다. 사내 환경의 리셋 시퀀스가 있으면 그것을 쓴다.
    wait (cfg_ctrl.vif.rst_n === 1'b1);
    repeat (10) @(posedge cfg_ctrl.vif.clk);

    seq = qch_quiesce_seq::type_id::create("seq");
    if (!seq.randomize() with { num_rounds == 20; })
      `uvm_error(get_type_name(), "randomize() failed on qch_quiesce_seq")

    // 상위가 하는 배선은 이 한 줄이다.
    seq.start(env_ctrl.ctrl_seqr);

    // 마지막 전이가 monitor 에 잡히도록 조금 더 돌린다.
    repeat (20) @(posedge cfg_ctrl.vif.clk);

    phase.drop_objection(this);
  endtask

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    // 커버리지는 각 env 의 agent 안에서 모인다. 값은 qch_coverage 의
    // report_phase 가 찍는다 (cfg.has_coverage 기본 1).
  endfunction

endclass

// ---------------------------------------------------------------------------
// bind 문 — 실제 신호 이름으로 바꿔 쓰는 부분
//
// bind 는 compilation unit scope 에 둔다. 사내 TB 에서는 이 블록만 떼어
// 파일 하나로 두는 편이 관리하기 쉽다.
//
// 주의: bind 대상 모듈 안에서 그 신호들이 보여야 한다. Q-Channel 포트가
// 서브모듈 경계에 있으면 그 서브모듈을 대상으로 bind 한다.
// ---------------------------------------------------------------------------
//
//  // VIP = controller. CPU 서브시스템의 device 측 포트에 붙인다.
//  bind cpu_subsystem qch_bind_controller u_qch_ctrl_bind (
//    .clk      (i_clk),          // <- 실제 클럭
//    .rst_n    (i_rst_n),        // <- 실제 리셋 (active-low 가 아니면 반전 필요)
//    .QREQn    (i_qreqn),        // VIP -> DUT : DUT 의 입력 포트
//    .QACCEPTn (o_qacceptn),     // DUT -> VIP
//    .QDENY    (o_qdeny),        // DUT -> VIP
//    .QACTIVE  (o_qactive)       // DUT -> VIP
//  );
//
//  // VIP = device. CRMU 의 requester 측 포트에 붙인다.
//  bind crmu qch_bind_device u_qch_dev_bind (
//    .clk      (i_clk),
//    .rst_n    (i_rst_n),
//    .QREQn    (o_qreqn),        // DUT -> VIP
//    .QACCEPTn (i_qacceptn),     // VIP -> DUT
//    .QDENY    (i_qdeny),        // VIP -> DUT
//    .QACTIVE  (i_qactive)       // VIP -> DUT
//  );
//
// 확인할 것
//   - DUT 입력 포트를 VIP 가 구동하려면 그 포트에 다른 구동자가 없어야 한다.
//     기존에 상수로 묶여 있으면(tie-off) 먼저 풀어야 한다.
//   - QDENY / QACTIVE 가 없는 구성(IHI0068D 2.1.4)이면 이 VIP 는 아직 지원하지
//     않는다. 임시로는 QDENY 를 0, QACTIVE 를 0 으로 묶어 붙일 수 있다.
//   - 클럭 도메인이 두 개면 인터페이스를 채널별로 따로 둔다 (지금 구조 그대로).

// ---------------------------------------------------------------------------
// TB top — 인터페이스 핸들을 넘기는 부분
//
// 핵심은 config_db::set 과 run_test() 가 같은 initial 블록 안에 있다는 것이다.
// bind 어댑터 안에서 set 하면 run_test() 보다 먼저 실행되는지가 시뮬레이터에
// 달려 있어, 늦으면 "vif 가 없다" fatal 로 끝난다.
//
// 사내 TB 가 이미 있으면 이 모듈을 쓰지 말고, 그쪽 run_test() 앞에
// uvm_config_db::set 두 줄만 추가하면 된다.
// ---------------------------------------------------------------------------
`ifdef QCH_EXAMPLE_TB
module qch_env_example_tb;

  // 사내 DUT top 을 여기 인스턴스한다. 아래 계층 경로는 그에 맞춰 바꾼다.
  // dut_top u_dut (...);

  initial begin
    // bind 로 꽂힌 어댑터 안의 인터페이스를 계층 참조로 집어 넘긴다.
    // 경로 = <bind 대상 인스턴스 경로>.<bind 인스턴스 이름>.u_qch_if
    //
    // uvm_config_db#(virtual qch_if)::set(null, "uvm_test_top", "vif_ctrl",
    //   u_dut.u_cpu_subsystem.u_qch_ctrl_bind.u_qch_if);
    //
    // uvm_config_db#(virtual qch_if)::set(null, "uvm_test_top", "vif_dev",
    //   u_dut.u_crmu.u_qch_dev_bind.u_qch_if);

    run_test("qch_env_example_test");
  end

endmodule
`endif // QCH_EXAMPLE_TB
