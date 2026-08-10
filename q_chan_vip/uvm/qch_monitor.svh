// ---------------------------------------------------------------------------
// qch_monitor
//
// 4 개 신호를 매 클럭 샘플링해서 상태를 복원하고, 상태가 바뀔 때마다
// qch_monitor_item 을 발행한다. 역할과 무관하게 항상 만들어진다.
//
// 이 monitor 는 어떤 프로토콜 위반도 보고하지 않는다. QCH_ST_ILLEGAL 에
// 진입해도 그 상태를 발행할 뿐 uvm_error 를 내지 않는다. 검사는 별도 SVA
// 증분이 담당하며, 여기서 중복하면 이중 관리 대상이 된다.
// ---------------------------------------------------------------------------
class qch_monitor extends uvm_monitor;

  `uvm_component_utils(qch_monitor)

  virtual qch_if.monitor vif;

  uvm_analysis_port #(qch_monitor_item) ap;

  local qch_state_e  cur_state;
  local int unsigned cycles_in_cur;
  local bit          tracking;  // 리셋 해제 후 초기 상태를 잡았는가

  function new(string name = "qch_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    virtual qch_if raw_vif;
    super.build_phase(phase);
    if (!uvm_config_db#(virtual qch_if)::get(this, "", "vif", raw_vif))
      `uvm_fatal(get_type_name(), "virtual interface 'vif' not set in config_db")
    vif = raw_vif;
  endfunction

  virtual task run_phase(uvm_phase phase);
    qch_state_e      sampled;
    qch_monitor_item it;

    tracking      = 1'b0;
    cycles_in_cur = 0;

    forever begin
      @(posedge vif.clk);

      // 리셋 중에는 상태를 추적하지 않는다.
      if (vif.rst_n !== 1'b1) begin
        tracking      = 1'b0;
        cycles_in_cur = 0;
        continue;
      end

      sampled = qch_decode_state(vif.QREQn, vif.QACCEPTn, vif.QDENY);

      // 리셋 해제 후 첫 샘플은 초기 상태로만 잡고 발행하지 않는다.
      if (!tracking) begin
        cur_state     = sampled;
        cycles_in_cur = 1;
        tracking      = 1'b1;
        continue;
      end

      if (sampled == cur_state) begin
        cycles_in_cur++;
      end
      else begin
        it                = qch_monitor_item::type_id::create("mon_it");
        it.prev_state     = cur_state;
        it.state          = sampled;
        it.qactive        = vif.QACTIVE;
        it.cycles_in_prev = cycles_in_cur;
        ap.write(it);

        cur_state     = sampled;
        cycles_in_cur = 1;
      end
    end
  endtask

endclass
