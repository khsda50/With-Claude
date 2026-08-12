// ---------------------------------------------------------------------------
// qch.f : Q-Channel VIP 컴파일 파일리스트
//
//   vcs  -sverilog -ntb_opts uvm -f qch.f
//   xrun -uvm -f qch.f
//
// +incdir 이 필요한 이유: 패키지가 .svh 를 `include 로 끌어온다.
// 이 파일리스트는 VIP 만 담는다. 테스트벤치와 DUT 는 상위 파일리스트에서 붙인다.
//
// 컴파일 순서 (바꾸면 깨진다)
//   1. qch_if.sv        인터페이스 — 패키지가 virtual qch_if 를 참조한다
//   2. qch_items.sv     qch_item_pkg — 아이템과 커버리지 어휘
//   3. qch_agent_pkg.sv qch_agent_pkg — config/monitor/coverage/driver/시퀀스/
//                        agent/env, 그리고 다중 채널용 virtual sequencer·multi_env·
//                        virtual 시퀀스
//   4. qch_bind.sv      bind 용 신호 어댑터 (모듈이라 패키지 밖)
// ---------------------------------------------------------------------------

+incdir+.

qch_if.sv
qch_items.sv
qch_agent_pkg.sv
qch_bind.sv

// --- 자체 테스트 (사내 환경에 붙일 때는 필요 없다) -------------------------
// 각 파일이 자기 top 모듈을 하나씩 갖고 있어 동시에 컴파일하면 top 이 여러 개가
// 된다. 하나씩 골라 돌린다.
//
// qch_items_unit_test.sv     top: qch_tb_top
// qch_monitor_test.sv        top: qch_mon_tb_top
// qch_controller_test.sv     top: qch_ctrl_tb_top
// qch_loopback_test.sv       top: qch_loopback_tb_top
// qch_coverage_test.sv       top: qch_cov_tb_top

// --- 사내 환경 붙이기 템플릿 ------------------------------------------------
// qch_env_example.sv
//   +define+QCH_EXAMPLE_TB 를 주면 예제 TB top 까지 컴파일된다.
//   보통은 이 파일을 복사해 사내 TB 에 맞게 고쳐 쓰고, 파일리스트에는 넣지 않는다.
