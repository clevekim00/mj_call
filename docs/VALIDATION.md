# 검증 기록 — 2026-11-03

- 이관 원본 SHA-256: 13개 파일 일치. `python3 scripts/verify_migration.py`.
- macOS 네이티브 앱: Xcode Debug, CODE_SIGNING_ALLOWED=NO 빌드 성공.
- iPhone/iPad 네이티브 앱: iOS Simulator Debug 빌드 성공.
- Android: 로컬에 Android SDK가 없어 로컬 빌드 미수행. Gradle wrapper 생성은 성공.
- Windows: 로컬에 .NET SDK·Windows 실행 환경이 없어 로컬 빌드 미수행.
- Android·Windows 및 Apple 빌드 CI 정의를 포함. 실제 CI 결과는 GitHub Actions에서 확인.
- 네이티브 앱의 단위·UI 테스트와 실기기 통화 품질은 아직 미검증.
- 공개 전 알려진 토큰·개인 키 형식과 녹음/서명 파일 확장자를 검사했으며 발견되지 않음. 전체 원본 저장소·실사용 자료는 복사하지 않음.
- 말이음에서 이관 패치와 현재 변경의 완전 일치를 확인한 뒤 통화 기능만 제거. 원본 작업 트리는 clean 상태로 복구됨.

기존 Flutter 테스트 16개 통과는 과거 구현의 기록이며 이번 네이티브 검증에 포함하지 않는다. AI 자동 통화는 구현·검증되지 않았다.
