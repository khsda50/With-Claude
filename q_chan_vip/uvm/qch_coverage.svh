// ---------------------------------------------------------------------------
// qch_coverage
//
// Q-Channel functional coverage. monitor 아이템만 구독한다.
//
// 자극 아이템(controller/device item)을 샘플하지 않는 것이 이 파일의 핵심 전제다.
// VIP 가 QCH_ROLE_PASSIVE 로 쓰이면 자극 아이템은 아예 생성되지 않으므로, 커버리지가
// 자극 측에 의존하면 그 구성에서 전부 0 이 된다. "무엇을 하려 했는가" 가 아니라
// "무엇이 일어났는가" 를 세는 쪽이 role 과 무관하게 성립한다.
//
// 프로토콜 위반은 여기서 판정하지 않는다. QCH_ST_ILLEGAL 도 illegal_bins 가 아니라
// 보통 bin 으로 둔다. illegal_bins 는 hit 되는 순간 시뮬레이터가 에러를 내므로
// "검사는 SVA, 관측은 monitor/coverage" 라는 이 VIP 의 역할 분리를 깨고 같은 사실을
// 두 곳에서 관리하게 된다. 대신 회귀 리포트에서 그 bin 이 0 이 아니면 눈에 띈다.
// ---------------------------------------------------------------------------
class qch_coverage extends uvm_subscriber #(qch_monitor_item);

  `uvm_component_utils(qch_coverage)

  // 샘플한 아이템 수. 커버리지 DB 를 열지 않고도 "샘플이 실제로 흘렀는가" 를
  // 단위 테스트에서 확인할 수 있게 남겨 둔다.
  int unsigned sampled_count;

  // -------------------------------------------------------------------------
  // covergroup
  //
  // 아이템 핸들을 넘기지 않고 스칼라로 풀어 넘긴다. 커버포인트 식 안에서 클래스
  // 핸들을 역참조하는 형태는 시뮬레이터 간 지원 차이가 있어, 인자로 받은 스칼라만
  // 쓰는 편이 이식성이 좋다.
  //
  // cycles_in_prev 는 문맥에 따라 뜻이 달라지는 필드다 (Q_REQUEST 를 떠날 때는
  // device 응답 지연, Q_RUN 을 떠날 때는 요청 전 유휴 시간, Q_STOPPED 를 떠날 때는
  // 조용히 머문 시간). 그래서 하나의 값을 prev_state 로 걸러 세 개의 커버포인트로
  // 나눈다. 필드 하나가 여러 지표를 겸하는 대신 샘플 조건이 지표를 가른다.
  // -------------------------------------------------------------------------
  covergroup cg_qch with function sample(qch_state_e        prev_state,
                                         qch_state_e        state,
                                         qch_trans_e        trans,
                                         qch_obs_response_e response,
                                         bit                qactive,
                                         int unsigned       cycles_in_prev);

    option.per_instance = 1;

    // --- 모든 전이에서 샘플되는 것 ---------------------------------------

    // IHI0068D Table 2-1 의 6 개 합법 상태 + Unused 조합.
    // exit/continue 는 SystemVerilog 예약어라 bin 이름에 밑줄을 붙인다.
    cp_state : coverpoint state {
      bins run       = {QCH_ST_RUN};
      bins request   = {QCH_ST_REQUEST};
      bins stopped   = {QCH_ST_STOPPED};
      bins exit_     = {QCH_ST_EXIT};
      bins denied    = {QCH_ST_DENIED};
      bins continue_ = {QCH_ST_CONTINUE};
      bins illegal   = {QCH_ST_ILLEGAL};  // 0 이어야 정상
    }

    // enum 자동 bin = 합법 전이 7 개 + QCH_TRANS_OTHER.
    // 이 커버포인트가 이 VIP 의 1 차 지표다. 7 개가 다 차면 handshake 의 두 경로
    // (accept 왕복, deny 왕복)를 모두 밟았다는 뜻이다.
    cp_trans : coverpoint trans;

    cp_qactive : coverpoint qactive {
      bins low  = {1'b0};
      bins high = {1'b1};
    }

    // --- Q_REQUEST 를 떠나는 전이에서만 샘플되는 것 -----------------------
    // 세 커버포인트가 같은 guard 를 쓰므로 아래 cross 도 같은 조건에서만 샘플된다.

    cp_response : coverpoint response iff (prev_state == QCH_ST_REQUEST) {
      bins accepted = {QCH_OBS_ACCEPTED};
      bins denied   = {QCH_OBS_DENIED};
      bins other    = {QCH_OBS_OTHER};  // 응답 없이 이탈 → SVA 대상, 0 이어야 정상
    }

    // device 응답 지연. monitor 가 상태 진입 시 1 로 시작해 매 클럭 올리므로
    // 0 은 구조상 나올 수 없다. 그래서 최소 bin 이 1 이다.
    cp_resp_latency : coverpoint cycles_in_prev iff (prev_state == QCH_ST_REQUEST) {
      bins one    = {1};
      bins short  = {[2:7]};
      bins medium = {[8:31]};
      bins long   = {[32:$]};
    }

    cp_qactive_at_resp : coverpoint qactive iff (prev_state == QCH_ST_REQUEST) {
      bins low  = {1'b0};
      bins high = {1'b1};
    }

    // 응답 x 지연: 거부가 즉시만 오고 느리게는 안 오는 식의 편향을 잡는다.
    x_response_latency : cross cp_response, cp_resp_latency;

    // 응답 x QACTIVE: "할 일이 남아 있다고 알리면서 수락" 같은 조합을 봤는지.
    // 아이템이 QACTIVE 를 handshake 와 독립된 필드로 들고 있어서 만들 수 있는
    // cross 다. QACTIVE 를 handshake 종속 필드로 설계했다면 이 칸이 생기지 않는다.
    x_response_qactive : cross cp_response, cp_qactive_at_resp;

    // --- 체류 시간 -------------------------------------------------------

    // 요청 직전까지 Q_RUN 에 머문 시간. 연속 요청(back-to-back)과 띄운 요청을
    // 모두 밟았는지 본다.
    cp_run_before_req : coverpoint cycles_in_prev
        iff (prev_state == QCH_ST_RUN && state == QCH_ST_REQUEST) {
      bins tight  = {1};
      bins short  = {[2:7]};
      bins spaced = {[8:$]};
    }

    // Q_STOPPED 체류 시간. 전력 관점에서 실제로 조용해진 구간의 길이.
    cp_stopped_dwell : coverpoint cycles_in_prev iff (prev_state == QCH_ST_STOPPED) {
      bins brief = {[1:3]};
      bins short = {[4:15]};
      bins long  = {[16:$]};
    }

  endgroup

  function new(string name = "qch_coverage", uvm_component parent = null);
    super.new(name, parent);
    cg_qch        = new();
    sampled_count = 0;
  endfunction

  // uvm_subscriber 의 순수 가상 메서드.
  virtual function void write(qch_monitor_item t);
    cg_qch.sample(t.prev_state,
                  t.state,
                  qch_classify_trans(t.prev_state, t.state),
                  qch_classify_response(t.prev_state, t.state),
                  t.qactive,
                  t.cycles_in_prev);
    sampled_count++;
  endfunction

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(),
              $sformatf("sampled %0d transitions, cg_qch = %0.2f%%",
                        sampled_count, cg_qch.get_inst_coverage()), UVM_LOW)
  endfunction

endclass
