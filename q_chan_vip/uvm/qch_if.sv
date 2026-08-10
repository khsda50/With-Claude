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
