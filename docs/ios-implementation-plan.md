# Folia iOS implementation plan

Goal: deliver an unsigned iPhoneOS arm64 IPA from GitHub Actions for iOS 26+, retaining online music and Folia lyrics with native controls and playback.

Architecture: SwiftUI features consume one native Omni contract. Provider transports own upstream cryptography and sessions. AVFoundation owns playback independently of WebKit. A separate bundled React entry reuses existing visualizers.

Tech stack: SwiftUI, Observation, AVFoundation, MediaPlayer, Security, CommonCrypto, WebKit, XcodeGen, React/Vite, XCTest and GitHub Actions.

Approved design: `docs/ios-migration-design.md`; user approved continuation and specified `L1angK1NG/folia-major-for-iPhone` on 2026-10-16. Execute without another architecture approval.

## Work packages

### 1. Repository and build environment

- [ ] Attach the existing source copy to the user's remote without overwriting working files; inspect differences before staging.
- [ ] Verify dependency availability and use the lockfile where possible. Record any upstream dependency inconsistencies.
- [ ] Add `ios/project.yml`, `ios/Folia/Info.plist`, `ios/Scripts/build-unsigned.sh` and `.github/workflows/ios-build.yml`.
- [ ] Build only with an installed iOS 26+ SDK; fail when the SDK or arm64 executable is missing. Package `Payload/Folia.app`, SHA-256 and logs. Never package a simulator app as an IPA.

### 2. Native contracts and platform protocols

Files: `ios/Folia/Domain/*.swift`, `ios/Folia/Services/*.swift`, `ios/FoliaTests/*Tests.swift`.

- [ ] Add tests for cross-provider identity, login capabilities, expired sessions, network error preservation, queue order and settings import rejection of local media.
- [ ] Start with `xcodebuild test` in Actions, record failures before implementing behavior; run portable protocol vectors locally where the same cryptographic reference can be exercised.
- [ ] Read pinned upstream request/encryption modules before implementing native transports. Keep passwords out of storage and output; Keychain stores sessions.
- [ ] Expose source-aware search, metadata, stream URL, lyrics, account, recommendations and collection operations through Omni. Unsupported operations must return a typed error.
- [ ] Implement only documented login capabilities. User actions trigger SMS, password submission and account mutations; read-only probes do not.
- [ ] Test queue and protocol vectors with XCTest, including cancellation and session replacement.

### 3. Native playback and interface

Files: `ios/Folia/Playback/*.swift`, `ios/Folia/App/*.swift`, `ios/Folia/Features/**/*.swift`.

- [ ] Native AVPlayer coordinator owns queue, playback position, background advance, expiring URL refresh, repeat/shuffle and Now Playing.
- [ ] Register remote commands once, remove observers, cancel stale resolution tasks, and preserve playback during orientation changes.
- [ ] SwiftUI tabs provide library, search, player and settings; accounts and collections open native sheets/navigation destinations.
- [ ] Use iOS 26 native glass controls, actual container-size layout, system sharing, accessibility and appearance preferences.
- [ ] Provide login, search, online queue, favorites, playlist/album/artist browsing and supported mutations using the public Omni boundary.
- [ ] Add native UI tests covering launch, navigation, rotation and reduced-motion fixtures. Fixture data is explicitly isolated to UI-test launch arguments.

### 4. Bundled lyrics

Files: `ios-web/index.html`, `ios-web/main.tsx`, `ios-web/bridge.ts`, `ios-web/vite.config.ts`, `ios/Folia/WebLyrics/*.swift`.

- [ ] Test bridge validation before implementation: reject stale song generations, malformed messages and unknown protocol versions.
- [ ] Reuse the existing registry and parsers; pass native snapshots through a versioned bridge. No audio element or full desktop App import.
- [ ] Interpolate time in the render layer; stop animation when hidden. Native playback continues when WebKit is suspended.
- [ ] Bundle assets with relative paths and preserve font/shader resources; report loading failures and retain readable native lyrics.

### 5. Integration and delivery

- [ ] Run focused tests and production lyrics bundle build. Run native tests and simulator screenshots on macOS Actions.
- [ ] Push reviewed changes only to the user-specified repository. Poll Actions and fix compile/runtime failures until required jobs pass.
- [ ] Download the resulting IPA into `artifacts/ios`, verify ZIP structure and SHA-256, and link the actual artifact in the final response.
- [ ] Update `docs/ios-implementation-status.md` and `ios/README.md` with implemented capabilities and remaining live-account/device validation. Do not equate mocks, unsigned packaging or simulator success with signed-device proof.

## Validation commands

Windows: `node --test ios-web/bridge.test.mjs`; `npm run build:ios-lyrics` after scripts are added.

macOS: `xcodegen generate --spec ios/project.yml`; `xcodebuild test -project ios/Folia.xcodeproj -scheme Folia -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO` (workflow selects an installed compatible simulator rather than assuming its name); `bash ios/Scripts/build-unsigned.sh`.

Acceptance: actual successful iPhoneOS build, native tests, bundled lyrics build and a downloadable unsigned IPA. Every original feature remains on the migration matrix until retained, explicitly removed as local-music functionality, or documented as an iOS limitation.
