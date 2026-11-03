# mj_call

마비말장애 사용자의 기관·고객센터 통화를 돕는 **플랫폼 네이티브 앱**입니다. 말이음(mj_dialog)의 통화 도우미를 독립 프로젝트로 분리했습니다.

별도 전화기로 발신하고 스피커폰을 켜면, 보조 기기가 입력한 문장을 읽고 선택적으로 마이크 소리를 녹음합니다. **현재는 수동 보조 단계이며 AI 자동 통화는 향후 구현 대상입니다.**

| 플랫폼 | 기술 | 프로젝트 |
|---|---|---|
| macOS | SwiftUI + AVFoundation | `apps/apple/MJCall.xcodeproj`, MJCall-macOS scheme |
| iOS · iPadOS | SwiftUI + AVFoundation | 같은 프로젝트, MJCall-iOS scheme (iPhone/iPad) |
| Android (AOS) | Kotlin + Android SDK Views | `apps/android` |
| Windows PC | C# · WPF + Windows Media APIs | `apps/windows/MJCall.csproj` |

Flutter는 실행에 사용하지 않습니다. 이전 구현은 `archive/flutter/`에 참고용으로 보관했습니다. 독립 패키지로 빌드되는 Dart 앱이 아닙니다.

## 기능과 문서

- 기관·고객센터 문의 목적·질문·연락처 준비 및 로컬 저장
- 입력한 글·준비 문장 한국어 TTS, 말하기 중지
- 안내·허락 확인 후 마이크 녹음, 중지·저장, 재생·삭제
- 문의 결과·메모 기록

[제품 기획](docs/PRODUCT.md) · [네이티브 설계](docs/ARCHITECTURE.md) · [구현/예정 기능과 검증 상태](docs/FEATURES.md) · [실행 방법](docs/BUILD.md) · [분리 이력](docs/MIGRATION.md) · [AI 프롬프트](prompts/README.md)

## 중요한 사용 조건

기기가 실제 전화번호로 발신하거나 전화를 끊지는 않습니다. 녹음은 마이크 수음이며 소음·에코가 섞일 수 있습니다. 기기의 한국어 음성과 마이크 권한이 필요합니다. 서명·배포·실기기 통화 품질은 별도 검증 대상입니다. 통화 자료는 앱 로컬 저장소에 남으며 이 초기 구현은 AI 서버로 전송하지 않습니다.

MIT License. 원본 프로젝트의 저작권 고지를 유지합니다.
