# 빌드와 실행

Flutter 설치가 필요하지 않습니다. 모든 프로젝트는 소스 실행용이며 배포용 서명 키를 포함하지 않습니다.

## macOS · iPhone · iPad
Xcode에서 `apps/apple/MJCall.xcodeproj`를 열고 `MJCall-macOS` 또는 `MJCall-iOS` scheme을 선택합니다. iOS 타깃은 iPhone·iPad를 지원하며 iOS/iPadOS 17 이상, macOS 타깃은 macOS 13 이상입니다. 실제 기기에서는 자신의 개발 팀/서명 설정이 필요합니다.

```sh
xcodebuild -project apps/apple/MJCall.xcodeproj -scheme MJCall-macOS -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project apps/apple/MJCall.xcodeproj -scheme MJCall-iOS -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```
마이크 허용·한국어 음성 설치·스피커 출력을 확인합니다. 녹음 허락 확인 후 시작합니다.

## Android
Android Studio, JDK 17, Android SDK 35가 필요합니다. `apps/android`를 열거나 다음을 실행합니다. 최소 Android 8/API 26입니다. `local.properties`와 개인 서명 키는 커밋하지 않습니다.

```sh
cd apps/android
./gradlew assembleDebug
```
Windows에서는 `gradlew.bat assembleDebug`를 사용합니다. 첫 실행은 Gradle/Android 플러그인을 다운로드합니다. 기기에서 마이크 권한과 한국어 TTS 엔진을 설정합니다.

## Windows PC
Windows 10 2004 이상을 대상으로 합니다. .NET 8 SDK와 Windows SDK를 설치한 후 실행합니다. 패키징과 스토어 서명은 아직 제공하지 않습니다.

```powershell
dotnet build apps/windows/MJCall.csproj -c Debug
dotnet run --project apps/windows/MJCall.csproj
```
Windows 개인정보 설정에서 데스크톱 앱 마이크 접근을 허용하고 한국어 음성 팩을 설치합니다.

## 검증
`python3 scripts/verify_migration.py`는 이관 원본의 해시를 확인합니다. `.github/workflows/native-build.yml`은 Apple·Android·Windows 빌드를 정의합니다. CI 결과와 실제 전화기 품질 검증은 서로 다릅니다.
