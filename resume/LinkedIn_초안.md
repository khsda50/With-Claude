# LinkedIn 프로필 초안 (한글)

> 목적: **이직 활동 노출**. 리크루터 검색에 걸리는 것이 1순위.
> 지원서(비공개 제출)와 달리 **전 세계 공개**이므로 고객사·공정 세대·과제명은 쓰지 않는다.
> 텍스트 블록은 한 문단이 한 줄 — 그대로 복사해 붙여넣을 수 있다.

---

## 1. Headline (220자)

```text
SoC/IP Design Verification 엔지니어 | UVM · SystemVerilog | CPU 서브시스템 · 인터커넥트 통합 검증 | In-house VIP 개발
```

- 92자. 리크루터 검색은 **영어 키워드**로 도는 경우가 많아 직무명과 기술명은 영문 그대로 둔다
- `Design Verification`, `UVM`, `SystemVerilog` 세 단어가 검색 노출의 대부분을 차지한다

---

## 2. About (2,600자 / 앞 3줄만 접히기 전에 보임)

```text
여러 IP가 통합된 시스템에서 검증되지 않은 지점을 찾아 테스트케이스를 만들고, IP 사이에서 발생하는 문제의 원인을 찾는 일을 해왔습니다. 인터커넥트, 부트, 전력 상태처럼 IP 하나만 봐서는 판단할 수 없는 구간을 주로 다뤘습니다.

필요한 검증 수단이 없으면 직접 만들었습니다. 상용 VIP가 없는 프로토콜은 스펙을 기반으로 In-house UVM VIP를 만들어 팀에 공유했고, 통합 후 동작을 판정할 방법이 없을 때는 스코어보드를 설계했습니다.

기억에 남는 일은 통과한 시뮬레이션에서 성능 결함을 찾은 것입니다. 판정은 통과였지만 소요 시간이 길어 파형을 열었고, 인터커넥트로 들어오는 트래픽은 burst인데 나가는 쪽이 single로 쪼개지고 있었습니다. 캐시 속성 설정을 원인으로 특정해 제어 수단을 추가했고, 소요 시간이 절반 이하로 줄었습니다. 같은 경로를 쓰는 다른 서브시스템에도 전파했습니다.

과제마다 검증 환경이 새로 만들어져 IP 단위와 Top 환경이 파편화돼 있던 것을 정리해, IP 단위 env와 시퀀스를 Top 통합 환경에서 그대로 재사용하는 구조를 설계했습니다. 현재 팀의 UVM 표준 구조로 쓰이고 있습니다.

앞으로는 한 IP를 스펙 단계부터 맡아 검증 항목을 세우고 커버리지로 닫는 일을 오래 하고 싶습니다. HBM을 비롯한 메모리 도메인에 관심을 두고 표준을 공부하고 있습니다.
```

- 공백·줄바꿈 포함 약 700자. LinkedIn About 은 길면 안 읽힌다
- **첫 문단이 접히기 전 노출 구간**이다. 여기서 "무엇을 하는 사람인지" 끝난다
- 지원서 C 의 사례를 옮기되 **고객사·IP 이름을 일반화**했다 (`CMN-700` → `인터커넥트`, `AxCACHE` → `캐시 속성 설정`)

---

## 3. Experience — 가온칩스 (2021.11 ~ 현재)

직무명: `SoC Design Verification Engineer`

```text
• CPU 서브시스템 UVM 검증 — 클러스터 기능 분석 기반 테스트케이스 개발, 시퀀스 및 FW 기반 검증 (진행 중)
• 인터커넥트 데이터패스 검증 — 통과한 시뮬레이션에서 성능 결함을 발견해 원인 특정 및 해결, 소요 시간 절반 이하 단축 후 유사 서브시스템에 전파
• Ethernet GMAC 통합·연동 검증 — UVM 환경 구성, constraint 기반 프레임/데이터 패턴 랜덤화, 정상 동작 판정 스코어보드 설계
• USB 2.0 IP 단위 검증 환경 구축 및 통합 검증, Mask ROM 부트 시나리오 검증
• Q/P-Channel In-house UVM VIP 개발 — 재사용 가능한 검증 환경으로 일원화
• UVM 검증 환경 표준화 — IP 단위 env·시퀀스를 Top 통합 환경에서 수직 재사용하는 구조 설계, 현재 팀 표준으로 사용 중
• 시뮬레이션 시간 단축 — 반복되던 초기화 구간을 저장·재사용하는 구조와 규칙 수립
• 사내 AI Transformation TF SoC 그룹 대표 — 검증 환경 이관 자동화 등 AI 적용 과제 기획
• IP Front-end Sign-off (Lint · CDC · LEC · Synthesis · STA), 서브시스템 RTL 설계
```

- 불릿 하나 = **무엇을 + 결과**. 지원서 문장을 그대로 옮기면 너무 길다
- `Cortex-A55`, `CMN-700`, `DSU` 같은 고유명은 **일반화**했다. 면접에서 물으면 그때 정확히 말하면 된다

---

## 4. Skills (상위 3개가 프로필에 노출)

```text
1. Design Verification
2. UVM (Universal Verification Methodology)
3. SystemVerilog
4. SoC Verification
5. Functional Verification
6. AMBA Protocol
7. Testbench Architecture
8. Verification IP (VIP)
9. RTL Design
10. Static Timing Analysis (STA)
11. Clock Domain Crossing (CDC)
12. Assertion-Based Verification (SVA)
13. Verilog
14. Python
15. HBM / DRAM (공부 중이면 넣지 않는다 — 아래 주의 참고)
```

- **상위 3개는 반드시 `Design Verification` / `UVM` / `SystemVerilog`.** 검색 노출이 여기서 결정된다
- 15번처럼 **아직 경험이 없는 것은 넣지 않는다.** Skill 은 동료 endorsement 대상이라 실물이 없으면 역효과

---

## 5. 설정 — 재직 중 이직 활동에서 반드시 챙길 것

| 설정 | 어떻게 |
|---|---|
| **Open to work** | **`Recruiters only`** 로 설정. 초록 배지(#OpenToWork)는 **공개**라 현 직장에 보인다 |
| **프로필 변경 알림** | Settings → Visibility → *Share profile updates with your network* **끄기**. 안 끄면 수정할 때마다 동료 피드에 뜬다 |
| **커스텀 URL** | `linkedin.com/in/이름-dv` 형태로 정리 |
| **지역** | 근무 희망지 기준으로 설정 (검색 필터에 걸린다) |
| **프로필 사진** | 있는 편이 열람률이 크게 높다 |

---

## 6. 포트폴리오 방향

DV 는 검증 자산이 사내 소유라 코드 공개가 어렵다. **문서로 보여주는 편이 실물에 가깝다.**

- **1순위 — 기술 문서 공개.** 프로토콜 정리, 설계 판단 기록. *"무엇을 한 건의 트랜잭션으로 볼 것인가"* 같은 판단은 코드보다 문서에서 잘 보인다. Notion 또는 블로그에 두고 **Featured 섹션에 링크**
- **2순위 — LinkedIn 글 2~3편.** 짧은 기술 정리. 프로필 체류 시간을 늘린다
- **`q_chan_vip` 저장소는 공개하지 않는다.** 실제 과제에 적용 중이므로 사내 자산으로 볼 여지가 있다. Experience 에 **한 줄로 언급만** 한다

---

## 7. 공개하지 않는 것 (지원서와 다른 점)

- 고객사명, 과제명
- **공정 세대 + 응용 분야 조합** (`2·3nm Chiplet HPC`, `8nm ADAS`) — 둘을 함께 쓰면 어느 과제인지 좁혀진다
- 고객사 자산 관련 서술 (`고객사 VIP 인수·확장`)
- 수상 내역의 세부 사유 — 이름만 쓰거나 생략
