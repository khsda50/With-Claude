// ---------------------------------------------------------------------------
// qch_coverage_test
//
// qch_coverage 단위 테스트. 두 층으로 나눠 확인한다.
//
//   1. 분류 함수 전수 검사 (순수 함수)
//      qch_classify_trans / qch_classify_response 를 7x7=49 개 상태쌍 전부에 대해
//      독립적으로 기술한 기대값과 비교한다. 시뮬레이터의 커버리지 엔진과 무관하게
//      항상 판정 가능한 부분이므로 여기서 확실히 잡는다.
//
//   2. 샘플링 경로 검사 (monitor -> coverage)
//      지향 시퀀스로 handshake 두 경로(accept 왕복 3 회, deny 왕복 2 회)를 구동하고,
//      monitor 가 발행한 전이 수와 coverage 가 샘플한 수가 일치하는지 본다.
//
// bin 단위 hit 여부는 여기서 단정하지 않는다. get_inst_coverage() 는 커버리지
// 수집을 켜고 컴파일했을 때만 의미 있는 값을 돌려주므로(예: VCS -cm line+cond+fsm+
// branch+assert 계열 옵션 없이는 0), 이것을 에러 조건으로 쓰면 옵션을 빼고 돌린
// 회귀에서 거짓 실패가 난다. 대신 값을 로그로 남겨 회귀 리포트에서 읽게 한다.
//
// 아래 지향 시퀀스가 채우는 bin (설계 의도):
//   cp_state          : illegal 제외 6 개
//   cp_trans          : 합법 7 개 전부 (QCH_TRANS_OTHER 는 0 이어야 정상)
//   cp_response       : accepted, denied (other 는 0 이어야 정상)
//   cp_resp_latency   : one(1), short(3,4), medium(10), long(40)
//   cp_qactive_at_resp: low, high
//   cp_run_before_req : tight(1), short(2,3,4), spaced(10)
//   cp_stopped_dwell  : brief(1), short(6), long(20)
//   x_response_qactive: 6 칸 중 4 칸 (other 행 2 칸은 0 이어야 정상)
//   x_response_latency: 12 칸 중 5 칸 (other 행 4 칸은 0 이어야 정상, 남는 3 칸
//                       accepted x long / denied x one / denied x medium 은 랜덤
//                       회귀 몫 — 지향 테스트로 전부 메우는 것은 목적이 아니다)
// ---------------------------------------------------------------------------
`include "uvm_macros.svh"
import uvm_pkg::*;
import qch_item_pkg::*;
import qch_agent_pkg::*;

class qch_coverage_test extends uvm_test;
  `uvm_component_utils(qch_coverage_test)

  uvm_analysis_imp #(qch_monitor_item, qch_coverage_test) mon_imp;
  qch_monitor_item collected[$];

  qch_monitor      mon;
  qch_coverage     cov;
  virtual qch_if   vif;

  function new(string name = "qch_coverage_test", uvm_component parent = null);
    super.new(name, parent);
    mon_imp = new("mon_imp", this);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual qch_if)::get(this, "", "vif", vif))
      `uvm_fatal(get_type_name(), "virtual interface 'vif' not set")
    mon = qch_monitor::type_id::create("mon", this);
    cov = qch_coverage::type_id::create("cov", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // analysis_port 는 다중 연결이 되므로 테스트의 기록용 imp 와 coverage 를
    // 같은 port 에 함께 붙인다.
    mon.ap.connect(mon_imp);
    mon.ap.connect(cov.analysis_export);
  endfunction

  virtual function void write(qch_monitor_item t);
    collected.push_back(t);
  endfunction

  // -------------------------------------------------------------------------
  // 1. 분류 함수 전수 검사
  // -------------------------------------------------------------------------

  // 구현(case 문)과 독립적으로 기대값을 평문 if 사슬로 다시 쓴다. 목적은 알고리즘
  // 재검증이 아니라 case 문의 누락/오타/분기 순서 실수를 잡는 것이다.
  function qch_trans_e expected_trans(qch_state_e p, qch_state_e s);
    if (p == QCH_ST_RUN      && s == QCH_ST_REQUEST)  return QCH_TRANS_RUN_REQ;
    if (p == QCH_ST_REQUEST  && s == QCH_ST_STOPPED)  return QCH_TRANS_REQ_STOP;
    if (p == QCH_ST_REQUEST  && s == QCH_ST_DENIED)   return QCH_TRANS_REQ_DENY;
    if (p == QCH_ST_STOPPED  && s == QCH_ST_EXIT)     return QCH_TRANS_STOP_EXIT;
    if (p == QCH_ST_EXIT     && s == QCH_ST_RUN)      return QCH_TRANS_EXIT_RUN;
    if (p == QCH_ST_DENIED   && s == QCH_ST_CONTINUE) return QCH_TRANS_DENY_CONT;
    if (p == QCH_ST_CONTINUE && s == QCH_ST_RUN)      return QCH_TRANS_CONT_RUN;
    return QCH_TRANS_OTHER;
  endfunction

  function qch_obs_response_e expected_response(qch_state_e p, qch_state_e s);
    if (p != QCH_ST_REQUEST)   return QCH_OBS_OTHER;
    if (s == QCH_ST_STOPPED)   return QCH_OBS_ACCEPTED;
    if (s == QCH_ST_DENIED)    return QCH_OBS_DENIED;
    return QCH_OBS_OTHER;
  endfunction

  task check_classifiers();
    qch_state_e all_states[];
    qch_trans_e        got_t, exp_t;
    qch_obs_response_e got_r, exp_r;
    int unsigned legal_count = 0;

    all_states = '{ QCH_ST_RUN, QCH_ST_REQUEST, QCH_ST_STOPPED, QCH_ST_EXIT,
                    QCH_ST_DENIED, QCH_ST_CONTINUE, QCH_ST_ILLEGAL };

    foreach (all_states[i])
      foreach (all_states[j]) begin
        got_t = qch_classify_trans   (all_states[i], all_states[j]);
        exp_t = expected_trans       (all_states[i], all_states[j]);
        got_r = qch_classify_response(all_states[i], all_states[j]);
        exp_r = expected_response    (all_states[i], all_states[j]);

        if (got_t != exp_t)
          `uvm_error("COV", $sformatf("classify_trans(%s, %s): expected %s, got %s",
                     all_states[i].name(), all_states[j].name(),
                     exp_t.name(), got_t.name()))

        if (got_r != exp_r)
          `uvm_error("COV", $sformatf("classify_response(%s, %s): expected %s, got %s",
                     all_states[i].name(), all_states[j].name(),
                     exp_r.name(), got_r.name()))

        if (got_t != QCH_TRANS_OTHER) legal_count++;
      end

    // 49 쌍 중 이름 있는 전이는 정확히 7 개여야 한다. 어떤 쌍이 실수로 합법으로
    // 분류되면 위 비교에서도 걸리지만, 개수 자체를 못 박아 두면 표가 늘어났을 때
    // 이 테스트를 같이 고치도록 강제된다.
    if (legal_count != 7)
      `uvm_error("COV", $sformatf("expected 7 named transitions among 49 pairs, got %0d",
                 legal_count))
  endtask

  // -------------------------------------------------------------------------
  // 2. 샘플링 경로 검사
  // -------------------------------------------------------------------------

  // negedge 에 구동하는 이유는 qch_monitor_test 와 같다. monitor 가 posedge 에
  // 샘플링하므로 posedge 에 값을 바꾸면 그 사이클의 관측값이 모호해진다.
  task drive_signals(bit qreqn, bit qacceptn, bit qdeny, bit qactive, int n = 1);
    @(negedge vif.clk);
    vif.QREQn    <= qreqn;
    vif.QACCEPTn <= qacceptn;
    vif.QDENY    <= qdeny;
    vif.QACTIVE  <= qactive;
    repeat (n) @(posedge vif.clk);
  endtask

  // IHI0068D Table 2-1 의 상태별 신호 조합
  task st_run     (int n, bit qactive = 1'b0); drive_signals(1'b1, 1'b1, 1'b0, qactive, n); endtask
  task st_request (int n, bit qactive = 1'b0); drive_signals(1'b0, 1'b1, 1'b0, qactive, n); endtask
  task st_stopped (int n, bit qactive = 1'b0); drive_signals(1'b0, 1'b0, 1'b0, qactive, n); endtask
  task st_exit    (int n, bit qactive = 1'b0); drive_signals(1'b1, 1'b0, 1'b0, qactive, n); endtask
  task st_denied  (int n, bit qactive = 1'b0); drive_signals(1'b0, 1'b1, 1'b1, qactive, n); endtask
  task st_continue(int n, bit qactive = 1'b0); drive_signals(1'b1, 1'b1, 1'b1, qactive, n); endtask

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    // 리셋 구간에도 Q_RUN 을 실어 둔다. 리셋 해제 후 첫 샘플이 초기 상태로 잡히는데,
    // 그때 다른 값이 실려 있으면 의도하지 않은 전이가 하나 더 발행된다.
    st_run(5);
    wait (vif.rst_n === 1'b1);

    // 초기 상태 Q_RUN 확정 (발행되지 않음)
    st_run(1);

    // --- accept 왕복 1: run_before_req=1(tight), latency=1(one), stopped=1(brief)
    st_request(1);
    st_stopped(1);
    st_exit   (1);
    st_run    (4);

    // --- accept 왕복 2: run_before_req=4(short), latency=4(short), stopped=6(short),
    //     응답 시점 QACTIVE HIGH ("할 일이 남았다고 알리면서 수락")
    st_request(4);
    st_stopped(6, 1'b1);
    st_exit   (1);
    st_run    (10);

    // --- accept 왕복 3: run_before_req=10(spaced), latency=10(medium), stopped=20(long)
    st_request(10);
    st_stopped(20);
    st_exit   (1);
    st_run    (2);

    // --- deny 왕복 1: latency=40(long), 응답 시점 QACTIVE LOW
    st_request (40);
    st_denied  (2);
    st_continue(2);
    st_run     (3);

    // --- deny 왕복 2: latency=3(short), 응답 시점 QACTIVE HIGH
    st_request (3);
    st_denied  (1, 1'b1);
    st_continue(1);
    st_run     (3);

    check_classifiers();
    check_sampling();

    phase.drop_objection(this);
  endtask

  task check_sampling();
    qch_trans_e exp_trans[$];
    qch_trans_e got;

    exp_trans = '{ QCH_TRANS_RUN_REQ, QCH_TRANS_REQ_STOP, QCH_TRANS_STOP_EXIT, QCH_TRANS_EXIT_RUN,
                   QCH_TRANS_RUN_REQ, QCH_TRANS_REQ_STOP, QCH_TRANS_STOP_EXIT, QCH_TRANS_EXIT_RUN,
                   QCH_TRANS_RUN_REQ, QCH_TRANS_REQ_STOP, QCH_TRANS_STOP_EXIT, QCH_TRANS_EXIT_RUN,
                   QCH_TRANS_RUN_REQ, QCH_TRANS_REQ_DENY, QCH_TRANS_DENY_CONT, QCH_TRANS_CONT_RUN,
                   QCH_TRANS_RUN_REQ, QCH_TRANS_REQ_DENY, QCH_TRANS_DENY_CONT, QCH_TRANS_CONT_RUN };

    // monitor 가 발행한 수와 coverage 가 샘플한 수가 같아야 한다. 다르면 analysis
    // 연결이 끊겼거나 write() 가 일부 아이템에서 빠진 것이다.
    if (cov.sampled_count != collected.size())
      `uvm_error("COV", $sformatf("coverage sampled %0d items but monitor published %0d",
                 cov.sampled_count, collected.size()))

    if (collected.size() != exp_trans.size()) begin
      `uvm_error("COV", $sformatf("expected %0d transitions, got %0d",
                 exp_trans.size(), collected.size()))
      foreach (collected[i])
        `uvm_info("COV", $sformatf("  [%0d] %s -> %s (%0d cycles, qactive=%0b)", i,
                  collected[i].prev_state.name(), collected[i].state.name(),
                  collected[i].cycles_in_prev, collected[i].qactive), UVM_LOW)
      return;
    end

    foreach (exp_trans[i]) begin
      got = qch_classify_trans(collected[i].prev_state, collected[i].state);
      if (got != exp_trans[i])
        `uvm_error("COV", $sformatf("transition %0d: expected %s, got %s (%s -> %s)",
                   i, exp_trans[i].name(), got.name(),
                   collected[i].prev_state.name(), collected[i].state.name()))
    end

    // 응답 지연 bin 을 실제로 의도한 값으로 밟았는지 확인한다. 지연 값이 어긋나면
    // latency 커버포인트가 엉뚱한 bin 에 들어가므로 커버리지 리포트만 봐서는
    // 눈치채기 어렵다. 여기서 값 자체를 못 박는다.
    //   collected[1]  = 왕복 1 의 REQ->STOPPED : Q_REQUEST 1 사이클  -> bin one
    //   collected[5]  = 왕복 2 의 REQ->STOPPED : 4 사이클            -> bin short
    //   collected[9]  = 왕복 3 의 REQ->STOPPED : 10 사이클           -> bin medium
    //   collected[13] = deny 1 의 REQ->DENIED  : 40 사이클           -> bin long
    check_latency(1,   1);
    check_latency(5,   4);
    check_latency(9,  10);
    check_latency(13, 40);

    // 응답 시점 QACTIVE. accept/deny 각각에서 HIGH 를 한 번씩 밟아야
    // x_response_qactive 4 칸이 다 찬다.
    if (collected[5].qactive !== 1'b1)
      `uvm_error("COV", "round 2 accept should be observed with QACTIVE high")
    if (collected[17].qactive !== 1'b1)
      `uvm_error("COV", "round 5 deny should be observed with QACTIVE high")
    if (collected[1].qactive !== 1'b0)
      `uvm_error("COV", "round 1 accept should be observed with QACTIVE low")
    if (collected[13].qactive !== 1'b0)
      `uvm_error("COV", "round 4 deny should be observed with QACTIVE low")

    `uvm_info("COV", $sformatf("cg_qch inst coverage = %0.2f%% (0 이면 커버리지 수집 옵션 없이 컴파일된 것)",
              cov.cg_qch.get_inst_coverage()), UVM_LOW)
  endtask

  function void check_latency(int idx, int unsigned exp_cycles);
    if (collected[idx].cycles_in_prev != exp_cycles)
      `uvm_error("COV", $sformatf("transition %0d: expected %0d cycles in Q_REQUEST, got %0d",
                 idx, exp_cycles, collected[idx].cycles_in_prev))
  endfunction

endclass

// ---------------------------------------------------------------------------
// 시뮬레이션 entry point
// ---------------------------------------------------------------------------
module qch_cov_tb_top;

  logic clk   = 1'b0;
  logic rst_n = 1'b0;

  always #5ns clk = ~clk;

  qch_if u_if (.clk(clk), .rst_n(rst_n));

  initial begin
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
  end

  initial begin
    uvm_config_db#(virtual qch_if)::set(null, "*", "vif", u_if);
    run_test("qch_coverage_test");
  end

endmodule
