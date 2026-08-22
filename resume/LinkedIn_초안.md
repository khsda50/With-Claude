# LinkedIn 프로필 & 포트폴리오 (한글)

> 목적: **이직 활동 노출.** 리크루터 검색에 걸리는 것이 1순위.
> **전 세계 공개** 매체이므로 고객사·공정 세대·과제명은 쓰지 않는다.
> 텍스트 블록은 한 문단이 한 줄 — 그대로 복사해 붙여넣을 수 있다.

---

## 0. 먼저 처리할 것

- [ ] **`With-Claude` 저장소를 Private 으로 전환** — 지원서 초안·약점 분석·탈락 이력·VIP 코드가 공개 상태다
- [ ] LinkedIn `Settings → Visibility → Share profile updates with your network` **끄기** (프로필 수정이 동료 피드에 뜬다)
- [ ] `Open to work` 는 **`Recruiters only`** 로. 초록 배지는 공개라 현 직장에 보인다
- [ ] 커스텀 URL 정리, 프로필 사진 등록

---

## 1. Headline

```text
SoC/IP Design Verification 엔지니어 | UVM · SystemVerilog | CPU 서브시스템 · 인터커넥트 통합 검증 | In-house VIP 개발
```

리크루터 검색은 영어 키워드로 돈다. `Design Verification` · `UVM` · `SystemVerilog` 는 반드시 원문 그대로 둔다.

---

## 2. About

```text
여러 IP가 통합된 시스템에서 검증되지 않은 지점을 찾아 테스트케이스를 만들고, IP 사이에서 발생하는 문제의 원인을 찾는 일을 해왔습니다. 인터커넥트, 부트, 전력 상태처럼 IP 하나만 봐서는 판단할 수 없는 구간을 주로 다뤘고, 참여한 과제 중에는 양산까지 간 SoC도 있습니다.

필요한 검증 수단이 없으면 직접 만들었습니다. 상용 VIP가 없는 프로토콜은 스펙을 기반으로 In-house UVM VIP를 만들어 팀에 공유했고, 통합 후 동작을 판정할 방법이 없을 때는 스코어보드를 설계했습니다. IP 단위 검증 환경과 전사에서 함께 쓰는 시뮬레이션 인프라도 구축해 왔습니다.

기억에 남는 일은 통과한 시뮬레이션에서 성능 결함을 찾은 것입니다. 판정은 통과였지만 소요 시간이 길어 파형을 열었고, 인터커넥트로 들어오는 트래픽은 burst인데 나가는 쪽이 single로 쪼개지고 있었습니다. 캐시 속성 설정을 원인으로 특정해 제어 수단을 추가했고 소요 시간이 절반 이하로 줄었습니다. 같은 경로를 쓰는 다른 서브시스템에도 전파했습니다.

과제마다 검증 환경이 새로 만들어져 IP 단위와 Top 환경이 파편화돼 있던 것을 정리해, IP 단위 env와 시퀀스를 Top 통합 환경에서 그대로 재사용하는 구조를 설계했습니다. 현재 팀의 UVM 표준 구조로 쓰이고 있습니다.

앞으로는 한 IP를 스펙 단계부터 맡아 검증 항목을 세우고 커버리지로 닫는 일을 오래 하고 싶습니다. HBM을 비롯한 메모리 도메인에 관심을 두고 표준을 공부하고 있습니다.
```

**첫 문단이 접히기 전 노출 구간**이다. 여기서 "무엇을 하는 사람인지"가 끝나야 한다.

---

## 3. Experience — 가온칩스 · SoC Design Verification Engineer (2021.11 ~ 현재)

```text
[IP · 서브시스템 검증]
• CPU 서브시스템 UVM 검증 — 클러스터 기능 분석 기반 테스트케이스 개발, 시퀀스 및 FW 기반 검증 (진행 중)
• 인터커넥트 데이터패스 검증 — 통과한 시뮬레이션에서 성능 결함을 발견해 원인 특정 및 해결, 소요 시간 절반 이하 단축 후 유사 서브시스템에 전파
• Ethernet GMAC 통합·연동 검증 — UVM 환경 구성, constraint 기반 프레임/데이터 패턴 랜덤화, 정상 동작 판정 스코어보드 설계
• USB 2.0 IP 단위 검증 환경 구축 및 통합 검증, Mask ROM 부트 시나리오 검증
• 데이터패스 라우팅 이슈 규명 및 Chiplet die 간 연결 사양 분석

[검증 환경 · VIP]
• Q/P-Channel In-house UVM VIP 개발 — 재사용 가능한 검증 환경으로 일원화
• 버스 연결성 검증 환경 자동화 — 설정 값에 따라 컴포넌트가 생성되는 구조에 스코어보드 설계
• 전사 IP 단위 시뮬레이션 환경 구축 — 회사 전체가 공용으로 사용
• Top/서브시스템 시뮬레이션 환경 구축·운영, 칩 구조 변경에 따른 Dual-die 환경 개편 리딩
• 커버리지 수집·DB 병합 플로우 구축, 양산 테스트(ATE)용 GLS 테스트벡터 추출

[방법론 · 설계]
• UVM 검증 환경 표준화 — IP 단위 env·시퀀스를 Top 통합 환경에서 수직 재사용하는 구조 설계, 현재 팀 표준으로 사용 중
• 시뮬레이션 시간 단축 — 반복되던 초기화 구간을 저장·재사용하는 구조와 규칙 수립
• 서브시스템 RTL 설계 및 IP Front-end Sign-off (Lint · CDC · LEC · Synthesis · STA)
• 사내 AI Transformation TF SoC 그룹 대표 — 검증 환경 이관 자동화 등 AI 적용 과제 기획

양산 tape-out 프로젝트를 포함해 IoT · 차량용 · Chiplet HPC 등 성격이 다른 SoC 과제에 참여했습니다.
```

- 고유명(`Cortex-A55` · `CMN-700` · `DSU` · `AxCACHE` · 공정 세대)은 **전부 일반화**했다. 면접에서 물으면 그때 정확히 말하면 된다
- 마지막 줄이 **양산 경험**과 **과제 다양성**을 한 문장으로 담는다. 공정 세대와 응용 분야를 함께 쓰면 고객사가 좁혀지므로 분리했다

---

## 4. Skills (상위 3개가 프로필에 노출)

```text
Design Verification / UVM / SystemVerilog
SoC Verification · Functional Verification · Testbench Architecture
AMBA Protocol · Verification IP (VIP) · Assertion-Based Verification (SVA)
RTL Design · Verilog · Static Timing Analysis · Clock Domain Crossing
Python · Simulation Infrastructure
```

**상위 3개는 반드시 `Design Verification` / `UVM` / `SystemVerilog`.** 검색 노출이 여기서 갈린다.
아직 경험이 없는 것(HBM·DRAM)은 넣지 않는다 — Skill 은 동료 endorsement 대상이다.

---

## 5. 나머지 섹션

| 섹션 | 채울 값 |
|---|---|
| **Education** | **[TODO]** 학교 · 전공 · 졸업연도 |
| **Honors & Awards** | 사내 베스트 엔지니어 — *IP 통합·인터커넥트 검증 성과* / 발급: 가온칩스 / **[TODO: 연도]** |
| **Languages** | 한국어(Native), 영어(Professional working) — **OPIc 등급은 쓰지 않는다** |
| **Projects** | IoT SoC · 차량용 SoC · Chiplet HPC SoC (공정 세대는 쓰지 않음) |

---

## 6. 포트폴리오

DV 는 검증 자산이 사내 소유라 코드 공개가 어렵다. **문서가 코드보다 실물에 가깝다** —
*무엇을 한 건의 트랜잭션으로 볼 것인가* 같은 판단은 코드로는 안 보이고 문서로만 보인다.

### 구성 (새 public 저장소 또는 Notion)

| # | 문서 | 재료 | 공개 가능 여부 |
|---|---|---|---|
| 1 | **Q-Channel VIP 설계 노트** — 무엇을 sequence_item 으로 볼 것인가, 후보 비교와 채택 근거 | `VIP_Q-Channel_seq-item설계.md` | **가능.** AMBA IHI0068D 는 공개 스펙이고 설계 판단은 본인 것. **사내 코드는 올리지 않는다** |
| 2 | **검사를 어디에 둘 것인가 — SVA · 스코어보드 · 시퀀스** | `UVM-VIP_구조_핵심정리.md` §9 | **가능.** 일반론이라 사내 정보가 없다 |
| 3 | **UVM 환경 수직 재사용 구조** — IP 단위 env 를 Top 에서 그대로 쓰는 방법 | 표준화 경험 | **가능.** 구조 원칙만 쓰고 과제·고객사는 빼면 된다 |
| 4 | **인터커넥트 성능 디버깅 사례** — 통과한 시뮬레이션에서 결함을 찾는 방법 | AxCACHE 건 | **조건부.** IP 이름·설정값을 빼고 *증상 → 관측 → 원인 추적* 방법론으로만 |

### 원칙

- **코드는 올리지 않는다.** `q_chan_vip` 은 실제 과제에 적용 중이므로 사내 자산으로 볼 여지가 있다
- 문서는 **공개 스펙 + 본인 판단** 으로만 구성한다
- LinkedIn **Featured 섹션에 2~3개 링크**. Featured 는 프로필 상단에 카드로 노출된다
- 문서 하나를 LinkedIn 글로 요약해 올리면 프로필 유입이 생긴다

---

## 7. 공개하지 않는 것

- 고객사명 · 과제명
- **공정 세대 + 응용 분야 조합** (`2·3nm Chiplet HPC`, `8nm ADAS`) — 함께 쓰면 과제가 특정된다
- 고객사 자산 관련 서술 (`고객사 VIP 인수·확장`)
- Coverage closure 관련 표현 — 인프라(`DB 병합 플로우`)까지만 쓰고 closure 는 말하지 않는다
- 급여 · 탈락 이력 · 약점 분석 (지금 public 저장소에 노출되어 있다 — 0번 항목 참고)
