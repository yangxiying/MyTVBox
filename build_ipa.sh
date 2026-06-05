#!/bin/bash
# build_ipa.sh - Build unsigned IPA for MyTVBox
# Usage: ./build_ipa.sh
set -e

PROJECT_NAME="MyTVBox"
SCHEME="MyTVBox"
CONFIGURATION="Release"
BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="${BUILD_DIR}/${PROJECT_NAME}.xcarchive"
IPA_DIR="${BUILD_DIR}/ipa"

echo "==> Generating Xcode project via xcodegen..."
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install with: brew install xcodegen"
  exit 1
fi
xcodegen generate

echo "==> Cleaning build directory..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

echo "==> Archiving (unsigned)..."
xcodebuild \
  -project "${PROJECT_NAME}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -sdk iphoneos \
  -archivePath "${ARCHIVE_PATH}" \
  archive \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM=""

echo "==> Packaging IPA..."
mkdir -p "${IPA_DIR}/Payload"
cp -R "${ARCHIVE_PATH}/Products/Applications/${PROJECT_NAME}.app" "${IPA_DIR}/Payload/"
cd "${IPA_DIR}"
zip -qr "${PROJECT_NAME}.ipa" Payload
cd -

echo "==> Done. IPA at: ${IPA_DIR}/${PROJECT_NAME}.ipa"
