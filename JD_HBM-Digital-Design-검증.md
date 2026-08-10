# SK hynix — HBM Digital Design (검증)

출처: `(KOR)8월 월간 hy-way_JD.pdf` p.11 (HBM&DRAM 개발 ⑥)
근무지: 이천 / 채용 레벨: **Junior & Expert** / 요구 경력: **4년 이상**

---

## 조직 소개

SK hynix HBM의 초격차 경쟁력 확보를 위해 **Analog-Digital Mixed IP, Digital IP 및
Subsystem/Top Level 검증** 업무를 맡고 있는 조직. HBM 제품 개발 과정에서 **설계 무결성 확보**를
목표로 설계 검증 전반을 담당하며, 이를 위한 **검증 시스템 및 환경 구축, 검증 모델 개발**을 수행.

## 담당 업무

1. HBM 내 In-house, 3rd Party Digital IP 및 Mixed 설계 검증
2. 검증을 위한 **In-house VIP 개발** 및 3rd Party VIP 도입/활용
3. **UVM 기반 검증 환경 구성 및 Test Case 개발**
4. **Regression Test를 통한 Code/Functional Coverage Closure**

## 자격 요건 (4년 이상 경력)

전공: 반도체/전자/전기/물리/컴퓨터 등 공학 계열

1. SystemVerilog/UVM VIP, Testbench 및 Test Case 개발 역량
2. Digital IP Spec 기반 **검증 계획 수립 및 검증 프로세스 이해** 역량
3. 신규 Protocol 또는 Custom IP에 대한 **UVM Agent 설계/구현** 역량
4. Code/Functional Coverage Closure

## 우대 사항

1. **Spec 기반 Custom UVM Agent A-to-Z 개발 경험**
2. HBM, DDR/LPDDR Memory 검증
3. Full-Chip Mixed-Level Design (Schematic & RTL) 검증

---

## 읽어낸 채용 의도 (자소서 각도)

- **"환경을 만드는 사람"을 뽑는 자리다.** 담당 업무 4개 중 2개(VIP 개발, 검증 환경 구성)가
  테스트 실행이 아니라 인프라 구축이다. "테스트케이스를 몇 개 짰다"가 아니라
  "없던 검증 환경을 세웠다"가 핵심 소구점.
- **Custom / 신규 IP 대응력이 진짜 필터다.** 요건 3번과 우대 1번이 같은 것을 두 번 말하고 있다
  (신규 Protocol·Custom IP에 대한 UVM Agent를 스펙만 보고 A-to-Z로 만들 수 있는가).
  HBM base die에는 표준 VIP가 없는 in-house IP가 많다는 뜻.
- **Mixed-Level 검증이 이 조직의 차별점.** 조직 소개 첫 줄이 "Analog-Digital Mixed IP"이고
  우대 3번이 Schematic & RTL 혼합 검증. 순수 디지털 검증만 한 지원자와 갈리는 지점.
- **Coverage Closure를 명시적으로 요구.** 정성적 "검증했다"가 아니라 정량 지표로 닫아본
  경험(회귀 인프라 운영 포함)을 숫자로 쓸 것.
- **Junior & Expert 동시 모집 + 4년**: 같은 HBM 라인의 다른 직무들(Front-end/Back-end/SoC는
  대부분 Expert·5년)보다 문턱이 낮다. 경력 연차보다 UVM 깊이로 승부 보는 자리.

## 인접 직무 (같은 PDF 내, 참고용)

| 직무 | 레벨 | 연차 | 성격 |
|---|---|---|---|
| 회로설계(HBM) | Junior & Expert | 4년+ | Full custom 회로/특성 분석 |
| HBM Digital Design (Front-end) | Expert | 5년+ | 합성·STA·DFT Implementation |
| HBM Digital Design (Back-end) | Expert | 5년+ | P&R, PDN |
| HBM Digital Design (RTL Design) | Expert | 4년+ | Base die RTL 설계 (Function 검증 포함) |
| **HBM Digital Design (SoC Design)** | Expert | 4년+ | Fullchip 설계 + **SoC/Logic Verification 환경·VIP 개발**, IP Integration 검증 (UCIe/PCIe/CXL, DRAM Controller), Test FW, Silicon validation |
| HBM PE | Expert | 5년+ | Wafer/Package Test, ATE |

> **SoC Design 직무도 검토 가치 있음** — 담당 업무에 "SoC & Digital Logic Verification 환경 및
> Verification IP 개발 및 검증", "Off-chip/Chiplet Interface IP Integration 및 검증",
> "Fullchip/Subsystem/IP 구동 Test Firmware 개발"이 그대로 들어있어, SoC 통합검증 +
> 펌웨어 구동 검증 이력과 겹치는 면적이 검증 직무 못지않다.
