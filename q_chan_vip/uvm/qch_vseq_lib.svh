// ---------------------------------------------------------------------------
// qch_vseq_lib
//
// 채널을 넘나드는 시퀀스. qch_virtual_sequencer 위에서 돈다.
//
// 채널 하나만 보는 시퀀스로 표현할 수 없는 것이 여기 들어간다. 전력 관리에서는
// "무엇을 먼저 조용히 시키는가" 가 곧 시나리오이므로, 순서를 쓰는 시퀀스가 필요하다.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// qch_vseq_base : p_sequencer 선언과 채널 하나를 몰아주는 공통 동작
// ---------------------------------------------------------------------------
class qch_vseq_base extends uvm_sequence;

  `uvm_object_utils(qch_vseq_base)
  `uvm_declare_p_sequencer(qch_virtual_sequencer)

  function new(string name = "qch_vseq_base");
    super.new(name);
  endfunction

  // 한 채널에 quiescence 왕복을 올린다.
  // 인자 이름이 qch_quiesce_seq 의 필드명과 겹치지 않게 지어서, with 절 안에서
  // 평범한 이름 해석으로 구분된다 (local:: 불필요).
  protected task run_channel(string       ch_name,
                             int unsigned rounds,
                             int unsigned gap  = 2,
                             int unsigned hold = 2);
    qch_quiesce_seq seq;
    seq = qch_quiesce_seq::type_id::create({"q_", ch_name});
    if (!seq.randomize() with { num_rounds  == rounds;
                                gap_cycles  == gap;
                                hold_cycles == hold; })
      `uvm_error(get_type_name(),
                 $sformatf("randomize() failed on qch_quiesce_seq (채널 %s)", ch_name))
    seq.start(p_sequencer.get_ctrl(ch_name));
  endtask

endclass

// ---------------------------------------------------------------------------
// qch_quiesce_all_seq : controller 역할인 모든 채널에 왕복을 돌린다.
//
// parallel = 0 : 등록 순서대로 하나씩 (한 채널이 끝나야 다음)
// parallel = 1 : 동시에. 채널 간 간섭을 보려면 이쪽.
//
// PASSIVE / DEVICE 채널은 건너뛴다. controller sequencer 가 없는 채널에
// start 하면 null 참조로 죽는다.
// ---------------------------------------------------------------------------
class qch_quiesce_all_seq extends qch_vseq_base;

  `uvm_object_utils(qch_quiesce_all_seq)

  rand int unsigned rounds_per_channel;
  bit               parallel = 1'b0;

  constraint c_rounds { soft rounds_per_channel inside {[1:5]}; }

  function new(string name = "qch_quiesce_all_seq");
    super.new(name);
  endfunction

  virtual task body();
    string nm;

    if (!parallel) begin
      foreach (p_sequencer.names[i]) begin
        nm = p_sequencer.names[i];
        if (p_sequencer.ctrl.exists(nm))
          run_channel(nm, rounds_per_channel);
      end
    end
    else begin
      // fork 안에서 쓰는 이름은 반복마다 새로 만들어져야 한다. automatic 변수를
      // 이름 있는 블록에 두는 것이 그 방법이다. 블록 이름을 붙이는 이유는 이름
      // 없는 블록의 선언을 툴이 거부하는 경우를 피하려는 것이다.
      foreach (p_sequencer.names[i]) begin : spawn_per_channel
        automatic string ch = p_sequencer.names[i];
        if (p_sequencer.ctrl.exists(ch))
          fork
            run_channel(ch, rounds_per_channel);
          join_none
      end
      wait fork;
    end
  endtask

endclass

// ---------------------------------------------------------------------------
// qch_quiesce_order_seq : 지정한 순서로 채널을 하나씩 조용히 시킨다.
//
// 전력 시퀀스의 실제 모양이다. 예: CPU -> L2 -> 인터커넥트 순으로 내리고,
// 깨울 때는 역순.
//
//   vseq       = qch_quiesce_order_seq::type_id::create("vseq");
//   vseq.order = '{"cpu", "l2", "noc"};
//   vseq.start(menv.vseqr);
//
// order 를 비워 두면 fatal 로 잡는다. 조용히 아무것도 하지 않고 지나가면
// 시나리오가 돌았다고 착각하게 된다.
// ---------------------------------------------------------------------------
class qch_quiesce_order_seq extends qch_vseq_base;

  `uvm_object_utils(qch_quiesce_order_seq)

  string       order[$];
  int unsigned rounds_per_channel = 1;

  // 각 채널을 조용히 시킨 뒤 다음으로 넘어가기 전 대기(Q_STOPPED 체류).
  int unsigned hold_cycles = 4;

  function new(string name = "qch_quiesce_order_seq");
    super.new(name);
  endfunction

  virtual task body();
    if (order.size() == 0)
      `uvm_fatal(get_type_name(),
                 "order 가 비어 있다. 조용히 통과하면 시나리오가 돌았다고 착각하게 된다")

    foreach (order[i]) begin
      `uvm_info(get_type_name(),
                $sformatf("[%0d/%0d] 채널 '%s' quiescence", i + 1, order.size(), order[i]),
                UVM_LOW)
      run_channel(order[i], rounds_per_channel, 0, hold_cycles);
    end
  endtask

endclass
