// ---------------------------------------------------------------------------
// qch_virtual_sequencer
//
// Q-Channel 이 여러 개인 DUT 에서 채널 간 순서를 하나의 시퀀스로 쓸 수 있게 하는
// 통로. 아이템을 직접 나르지 않고, 채널별 sequencer 핸들만 들고 있다.
//
// 전력 관리에서 채널 간 순서는 의미를 가진다. "CPU 를 먼저 조용히 시키고, 그
// 다음 L2, 마지막에 인터커넥트" 같은 시나리오는 채널 하나만 보는 시퀀스로는
// 표현할 수 없다. 그래서 채널을 넘나드는 시퀀스가 필요하고, 그것이 올라갈 자리가
// 이 sequencer 다.
//
// 이름으로 찾는다. 인덱스로 찾으면 채널이 하나 늘거나 순서가 바뀔 때 시퀀스가
// 조용히 다른 채널을 건드리게 된다.
// ---------------------------------------------------------------------------
class qch_virtual_sequencer extends uvm_sequencer;

  `uvm_component_utils(qch_virtual_sequencer)

  // 채널 이름 -> 그 채널의 sequencer.
  // role 에 따라 일부만 채워진다.
  //   CONTROLLER 채널 : ctrl 에만
  //   DEVICE 채널     : rsp, act 에
  //   PASSIVE 채널    : 어디에도 없음 (관측 전용)
  qch_controller_sequencer      ctrl[string];
  qch_device_response_sequencer rsp[string];
  qch_device_active_sequencer   act[string];

  // 등록된 순서를 그대로 보존한 채널 이름 목록.
  //
  // 연관 배열의 foreach 순회는 키의 사전순이라 등록 순서와 다르다. 전력 시퀀스는
  // 순서가 곧 의미이므로, 순서를 쓰려면 이 목록을 써야 한다.
  string names[$];

  function new(string name = "qch_virtual_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // 이름을 잘못 쓴 경우를 조용히 넘기지 않는다. null sequencer 에 start 하면
  // 원인을 찾기 어려운 곳에서 죽는다.
  function qch_controller_sequencer get_ctrl(string ch_name);
    if (!ctrl.exists(ch_name))
      `uvm_fatal(get_type_name(),
                 $sformatf("controller 채널 '%s' 가 없다 (등록된 채널: %p)", ch_name, names))
    return ctrl[ch_name];
  endfunction

  function qch_device_response_sequencer get_rsp(string ch_name);
    if (!rsp.exists(ch_name))
      `uvm_fatal(get_type_name(),
                 $sformatf("device 채널 '%s' 가 없다 (등록된 채널: %p)", ch_name, names))
    return rsp[ch_name];
  endfunction

  function qch_device_active_sequencer get_act(string ch_name);
    if (!act.exists(ch_name))
      `uvm_fatal(get_type_name(),
                 $sformatf("device 채널 '%s' 가 없다 (등록된 채널: %p)", ch_name, names))
    return act[ch_name];
  endfunction

endclass
