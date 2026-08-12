// ---------------------------------------------------------------------------
// qch_bind_* : bind 용 신호 어댑터
//
// qch_if 의 4 개 신호는 인터페이스 내부 변수라서 bind 로 DUT 신호에 직접
// 이어붙일 수 없다. 그래서 포트를 가진 얇은 모듈을 하나 두고, 그 안에서
// qch_if 를 인스턴스한 뒤 방향에 맞게 연결한다. bind 대상은 이 모듈이다.
//
// 역할별로 모듈을 나눈 이유는 방향 때문이다. SystemVerilog 는 같은 변수에
// 절차적 대입(driver 가 vif.QREQn <= ... 하는 것)과 연속 대입(assign)을 동시에
// 하는 것을 허용하지 않는다. 그러므로 VIP 가 구동하는 신호는 인터페이스에서
// 읽어 나가고(assign 출력), VIP 가 관측하는 신호는 인터페이스로 밀어넣는다
// (assign 입력). 어느 쪽인지는 role 이 정한다.
//
//   qch_bind_controller : VIP 가 QREQn 을 구동. 없는 CRMU 를 대신할 때.
//   qch_bind_device     : VIP 가 QACCEPTn/QDENY/QACTIVE 를 구동. 없는 CPU 측을
//                         대신할 때 (responder).
//   qch_bind_passive    : 아무것도 구동하지 않고 관측만. 양쪽 RTL 이 다 있을 때.
//
// 인터페이스 핸들은 config_db 에 넣지 않고 `u_qch_if` 로 노출만 한다.
// 이유: 모듈 안 initial 블록에서 config_db::set 을 하면 run_test() 의
// build_phase 보다 먼저 실행되는지가 시뮬레이터 구현에 달려 있다. 늦게 실행되면
// "vif 가 없다" 라는 fatal 로 끝나고 원인 찾기가 번거롭다. 그래서 TB top 이
// run_test() 직전에 계층 참조로 핸들을 넘기게 한다 — 한 initial 블록 안이라
// 순서가 결정적이다. 사용 예는 qch_env_example.sv 참조.
// ---------------------------------------------------------------------------
`ifndef QCH_BIND_SV
`define QCH_BIND_SV

// ---------------------------------------------------------------------------
// VIP = Controller. QREQn 을 구동하고 나머지를 관측한다.
// ---------------------------------------------------------------------------
module qch_bind_controller (
  input  logic clk,
  input  logic rst_n,
  output logic QREQn,     // VIP -> DUT
  input  logic QACCEPTn,  // DUT -> VIP
  input  logic QDENY,     // DUT -> VIP
  input  logic QACTIVE    // DUT -> VIP
);

  qch_if u_qch_if (.clk(clk), .rst_n(rst_n));

  assign QREQn             = u_qch_if.QREQn;
  assign u_qch_if.QACCEPTn = QACCEPTn;
  assign u_qch_if.QDENY    = QDENY;
  assign u_qch_if.QACTIVE  = QACTIVE;

endmodule

// ---------------------------------------------------------------------------
// VIP = Device. QACCEPTn/QDENY/QACTIVE 를 구동하고 QREQn 을 관측한다.
// ---------------------------------------------------------------------------
module qch_bind_device (
  input  logic clk,
  input  logic rst_n,
  input  logic QREQn,     // DUT -> VIP
  output logic QACCEPTn,  // VIP -> DUT
  output logic QDENY,     // VIP -> DUT
  output logic QACTIVE    // VIP -> DUT
);

  qch_if u_qch_if (.clk(clk), .rst_n(rst_n));

  assign u_qch_if.QREQn = QREQn;
  assign QACCEPTn       = u_qch_if.QACCEPTn;
  assign QDENY          = u_qch_if.QDENY;
  assign QACTIVE        = u_qch_if.QACTIVE;

endmodule

// ---------------------------------------------------------------------------
// VIP = Passive. 4 개 전부 관측만.
// ---------------------------------------------------------------------------
module qch_bind_passive (
  input logic clk,
  input logic rst_n,
  input logic QREQn,
  input logic QACCEPTn,
  input logic QDENY,
  input logic QACTIVE
);

  qch_if u_qch_if (.clk(clk), .rst_n(rst_n));

  assign u_qch_if.QREQn    = QREQn;
  assign u_qch_if.QACCEPTn = QACCEPTn;
  assign u_qch_if.QDENY    = QDENY;
  assign u_qch_if.QACTIVE  = QACTIVE;

endmodule

`endif // QCH_BIND_SV
