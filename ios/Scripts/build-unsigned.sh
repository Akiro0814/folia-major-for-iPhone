#!/bin/bash
# ios/Scripts/build-unsigned.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/artifacts/ios"
mkdir -p "$OUT"
xcodebuild -version | tee "$OUT/toolchain.txt"
xcrun --sdk iphoneos --show-sdk-version | tee -a "$OUT/toolchain.txt"
python3 -c 'import sys; assert int(sys.argv[1].split(".")[0]) >= 26, "iOS 26 SDK required"' "$(xcrun --sdk iphoneos --show-sdk-version)"
xcodebuild build -project "$ROOT/ios/Folia.xcodeproj" -scheme Folia \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$OUT/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" | tee "$OUT/build.log"
APP="$OUT/DerivedData/Build/Products/Release-iphoneos/Folia.app"
test -f "$APP/Folia"
test -f "$APP/Lyrics/index.html"
xcrun lipo -verify_arch arm64 "$APP/Folia"
file "$APP/Folia" | tee "$OUT/executable.txt"
STAGE="$(mktemp -d "$OUT/package.XXXXXX")"
mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/Folia.app"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/Payload" "$OUT/Folia-iOS-unsigned.ipa"
python3 "$ROOT/ios/Scripts/verify-ipa.py" "$OUT/Folia-iOS-unsigned.ipa"
(cd "$OUT" && shasum -a 256 Folia-iOS-unsigned.ipa > Folia-iOS-unsigned.ipa.sha256)
