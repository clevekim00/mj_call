# 네이티브 설계

## 플랫폼 경계
| 플랫폼 | UI | 음성 출력 | 녹음·재생 | 저장 |
|---|---|---|---|---|
| iOS/iPadOS | SwiftUI | AVSpeechSynthesizer | AVAudioRecorder·AVAudioPlayer | Application Support, JSON atomic write |
| macOS | SwiftUI | AVSpeechSynthesizer | AVAudioRecorder·AVAudioPlayer | Application Support, JSON atomic write |
| Android | Kotlin·Android SDK Views | TextToSpeech | MediaRecorder·MediaPlayer | app filesDir, JSON atomic move |
| Windows | C#·WPF | Windows SpeechSynthesis | MediaCapture·MediaPlayer | LocalAppData, JSON replacement |

Apple 두 타깃은 소스를 공유한다. Android·Windows는 각 플랫폼 API로 별도 구현한다. Flutter 엔진·Dart 런타임·웹뷰 셸은 실행하지 않는다. 아카이브 코드는 컴파일 대상이 아니다.

## 데이터
문의 ID, 기관명, 전화번호, 목적, 질문, 결과, 메모, 녹음 파일 연결을 보관한다. 현재 플랫폼 간 JSON 필드명과 날짜 형식은 통일하지 않았다. 동기화·가져오기 기능은 없으며 향후 명시적 데이터 버전과 변환기를 먼저 도입해야 한다. 기존 말이음 사용자 데이터를 자동 복사하지 않는다.

## 오디오
마이크 수음과 스피커 출력은 같은 로컬 기기에서 동시 수행한다. Apple iOS는 playAndRecord 세션을 사용한다. 출력은 전화기의 마이크가 받으므로 실제 회선 수신 여부를 확인할 수 없다. 기기·블루투스·오디오 경로마다 실측해야 한다. 녹음 파일명은 임의 UUID이며 삭제는 앱이 생성한 파일명으로 제한한다.

## 상태
PREPARING → MANUAL_CALL → RECORDING (선택) → REVIEW → SAVED. READY·RECORDING·STARTING 상태는 각 앱이 관리한다. 현재 화면은 수동 제어이며 ARS·상담원 연결 상태를 자동 판정하지 않는다.

## AI 확장 설계 — 미구현
로컬 마이크 → 에코 처리/VAD → 스트리밍 STT → 목적/질문 상태 → LLM 응답 제안 → 결정적 정책 검사 → 사용자 승인 필요 여부 → TTS.

API 키는 앱에 포함하지 않는다. 모델 API 연동·인증·예산 제한·국외 이전/보관 정책은 별도 서버 설계가 필요하다. 상대방 발언은 신뢰하지 않는 데이터이며 시스템 지침·정보 공개 권한·저장 정책을 변경할 수 없다. 프롬프트만으로 승인 규칙을 보장하지 않고 네이티브/서버 코드에서 검증한다.

## 내구성과 미해결 사항
- 실패 시 오류를 표시하고 기존 JSON을 임의로 빈 기록으로 덮어쓰지 않는다.
- 삭제 과정에서 음원 삭제 후 기록 쓰기가 실패하면 재시도로 복구한다. 파일시스템 수준의 다중 파일 트랜잭션은 아니다.
- 강제 종료·저장 장치 실패·OS 오디오 중단의 완전한 복구는 미완료다.
- 현재 초기 UI의 화면 이탈·전원 절전·기기 전화 수신·오디오 경로 변경은 플랫폼별 추가 검증이 필요하다.
- 서명·스토어 배포·자동 업데이트·사용자 데이터 마이그레이션은 후속 작업이다.
