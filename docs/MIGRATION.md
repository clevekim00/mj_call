# mj_dialog에서 mj_call로 분리

2026-11-03. 사용자 요청: 말이음과 목적이 다른 통화 도우미를 별도 공개 프로젝트로 분리하고 Flutter를 사용하지 않는다.

## 옮긴 것
- docs/history/blueprint-assisted-phone-call.md: 원본 전체 기획·워크플로·예정 기능.
- docs/history/flutter-implementation.md: 기존 구현과 16개 테스트의 역사 기록.
- archive/flutter/lib/features/call_assist/: 실제 구현 전체.
- archive/flutter/test/: 관련 테스트.
- archive/flutter/lib/services/: 참조한 오디오·권한 서비스.
- archive/flutter/source-integration.patch: 말이음 오늘/기록 진입, iOS TTS, 패키지 등록을 포함한 정확한 변경 패치.
- docs/history/migration-manifest.json: 원본 파일과 이관 파일의 SHA-256.

기존에 별도 통화 AI 시스템 프롬프트 파일은 없었다. prompts/의 세 템플릿은 기존 기획의 의도·승인 규칙을 바탕으로 이번에 새로 작성했으며 앱에서 실행하지 않는다. 대화 전체·사용자 프로필·실제 통화 기록·서명/인증 자료는 공개 저장소에 포함하지 않는다.

## 새로 만든 것
SwiftUI Apple 앱, Kotlin Android 앱, C#/WPF Windows 앱의 네이티브 초기 구현. 플랫폼별 빌드 파일, 네이티브 설계, 구현/예정 기능 구분, 향후 AI 프롬프트, GitHub Actions.

## 원본 앱 정리
이번 대화에서 추가한 통화 전용 코드·문서·메뉴·의존성·네이티브 채널만 되돌린다. 기존 재활 기능과 기존 녹음·TTS는 유지한다. 원본 변경이 이관 패치와 같은지 검사하고 파일 해시를 확인한 뒤 제거한다. 원본 프로젝트의 커밋 기록이나 실사용 데이터를 새 저장소에 통째로 복사하지 않는다.

## 호환성
Flutter 소스는 역사 참고용이며 실행 의존성이 아니다. 각 네이티브 UI는 초기 재구현으로, 이전 버전의 모든 실패 처리/접근성 검증이 동등하게 이식된 상태는 아니다. 기존 녹음의 자동 이관·데이터 형식 통일은 후속 과제다.
