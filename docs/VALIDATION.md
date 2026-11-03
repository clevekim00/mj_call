# 검증 기록 — 2026-11-03

- 이관 원본 SHA-256: 13개 파일 일치. `python3 scripts/verify_migration.py`.
- macOS 네이티브 앱: Xcode Debug, CODE_SIGNING_ALLOWED=NO 빌드 성공.
- iPhone/iPad 네이티브 앱: iOS Simulator Debug 빌드 성공.
- Android: GitHub Actions에서 assembleDebug 성공. 로컬 Android SDK는 설치하지 않음.
- Windows: GitHub Actions에서 .NET 8 WPF 빌드 성공. 로컬 Windows 실행은 미수행.
- Apple 두 타깃·Android·Windows 모두 [네이티브 빌드 CI](https://github.com/clevekim00/mj_call/actions/runs/41622354439)에서 성공. 확인한 네이티브 소스 커밋: 08d8a60139c61e1ff698b733488d32eca04361cb.
- 네이티브 앱의 단위·UI 테스트와 실기기 통화 품질은 아직 미검증.
- 공개 전 알려진 토큰·개인 키 형식과 녹음/서명 파일 확장자를 검사했으며 발견되지 않음. 전체 원본 저장소·실사용 자료는 복사하지 않음.
- 말이음에서 이관 패치와 현재 변경의 완전 일치를 확인한 뒤 통화 기능만 제거. 원본 작업 트리는 clean 상태로 복구됨.

기존 Flutter 테스트 16개 통과는 과거 구현의 기록이며 이번 네이티브 검증에 포함하지 않는다. AI 자동 통화는 구현·검증되지 않았다.
