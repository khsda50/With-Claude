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
