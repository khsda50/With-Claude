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
  `include "qch_coverage.svh"
  `include "qch_sequencers.svh"
  `include "qch_controller_driver.svh"
  `include "qch_device_driver.svh"
  `include "qch_responder_seq.svh"
  `include "qch_seq_lib.svh"
  `include "qch_agent.svh"
  `include "qch_env.svh"

  // 다중 채널. 채널마다 qch_env 를 하나 두고, 채널을 넘나드는 시퀀스는
  // virtual sequencer 위에서 돈다.
  `include "qch_virtual_sequencer.svh"
  `include "qch_multi_env.svh"
  `include "qch_vseq_lib.svh"

endpackage
