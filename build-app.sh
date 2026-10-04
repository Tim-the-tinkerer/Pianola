#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

LAUNCH=true
for arg in "$@"; do
    case "${arg}" in
        --no-launch) LAUNCH=false ;;
    esac
done

APP="Pianola.app"
BUNDLE_ID="com.pianola.app"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' AppInfo.plist 2>/dev/null || true)"
VERSION="${VERSION:-1.0.0}"

if [[ ! -f Assets/AppIcon.icns ]]; then
    echo "Generating app icon..."
    swift Scripts/GenerateAppIcon.swift
fi

echo "Building Pianola ${VERSION} (release)..."
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="${BIN_DIR}/Pianola"
if [[ ! -x "${BIN}" ]]; then
    echo "error: expected binary not found at ${BIN}" >&2
    exit 1
fi

echo "Self-test..."
"${BIN}" --self-test

echo "Assembling ${APP}..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources/MIDI"
cp "${BIN}" "${APP}/Contents/MacOS/Pianola"
chmod +x "${APP}/Contents/MacOS/Pianola"
cp AppInfo.plist "${APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleGetInfoString Pianola ${VERSION}" \
    "${APP}/Contents/Info.plist" 2>/dev/null || true

if [[ -d .build/release/Pianola_Pianola.bundle ]]; then
    cp -R .build/release/Pianola_Pianola.bundle "${APP}/Contents/Resources/"
fi

if [[ -d Sources/Pianola/Resources/MIDI ]]; then
    cp -R Sources/Pianola/Resources/MIDI/. "${APP}/Contents/Resources/MIDI/"
fi

if [[ -f Assets/AppIcon.icns ]]; then
    cp Assets/AppIcon.icns "${APP}/Contents/Resources/"
fi

echo "Signing ${APP}..."
xattr -cr "${APP}" 2>/dev/null || true
codesign --force --sign - --identifier "${BUNDLE_ID}" --timestamp=none "${APP}/Contents/MacOS/Pianola"
codesign --force --sign - --identifier "${BUNDLE_ID}" --timestamp=none "${APP}"

plutil -lint "${APP}/Contents/Info.plist" >/dev/null
codesign --verify --verbose=2 "${APP}" 2>/dev/null || codesign --verify "${APP}"

if [[ -x /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister ]]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(pwd)/${APP}" 2>/dev/null || true
fi

echo "Done: ${APP} (v${VERSION})"
if [[ "${LAUNCH}" == "true" ]]; then
    pkill -x Pianola 2>/dev/null || true
    sleep 0.2
    echo "Launching..."
    open "${APP}"
fi
