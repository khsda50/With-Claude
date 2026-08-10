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
