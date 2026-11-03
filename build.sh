#!/bin/bash
# Builds FlickOff.app from the Swift package.
#   ./build.sh            unit tests, release build -> build/FlickOff.app, self-test
#   ./build.sh test       unit tests only (hardware tests: TB_HARDWARE_TESTS=1 ./build.sh test)
#   ./build.sh install    unit tests, build, open the native installer
set -euo pipefail
cd "$(dirname "$0")"

APP=build/FlickOff.app
ARCH=arm64

# The Command Line Tools keep the Swift Testing macro plugin outside the default search path.
DEV_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
TEST_FLAGS=()
BUILD_FLAGS=()
# Some managed development environments cannot start SwiftPM's nested sandbox.
# Opt in explicitly; keep it enabled for ordinary local builds.
if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == 1 ]]; then
    BUILD_FLAGS+=(--disable-sandbox)
fi
if [[ "$DEV_DIR" == *CommandLineTools* && -d "$DEV_DIR/usr/lib/swift/host/plugins/testing" ]]; then
    TEST_FLAGS=(-Xswiftc -plugin-path -Xswiftc "$DEV_DIR/usr/lib/swift/host/plugins/testing")
fi


run_tests() {
    swift test ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"} ${TEST_FLAGS[@]+"${TEST_FLAGS[@]}"}
}

build_app() {
    swift build ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"} -c release --arch "$ARCH" -debug-info-format none
    local bin
    bin="$(swift build ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"} -c release --arch "$ARCH" -debug-info-format none --show-bin-path)/FlickOff"

    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$bin" "$APP/Contents/MacOS/FlickOff"
    cp Resources/Info.plist "$APP/Contents/Info.plist"
    local actual_arch
    actual_arch="$(lipo -archs "$APP/Contents/MacOS/FlickOff")"
    if [[ "$actual_arch" != "$ARCH" ]]; then
        echo "error: expected $ARCH executable, found $actual_arch" >&2
        exit 1
    fi
    python3 scripts/embed_sparkle.py "$APP" "$ARCH"
    cp -R Resources/*.lproj "$APP/Contents/Resources/"
    cp LICENSE NOTICE COMMERCIAL.md THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
    swift scripts/make_icon.swift build/icon-assets
    iconutil -c icns build/icon-assets/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
    plutil -lint "$APP/Contents/Info.plist"
    codesign --force --sign - "$APP"
    codesign --verify --deep --strict "$APP"
    echo "built $APP"
}

# Report only: a build machine without a Touch Bar legitimately fails it.
self_test() {
    "$1/Contents/MacOS/FlickOff" --self-test || echo "warning: self-test failed on this Mac (see report above)"
}

# Check bundle launch and setup guidance without changing brightness or login items.
smoke_test() {
    local output
    output="$("$1/Contents/MacOS/FlickOff" --setup-info)"
    if ! grep -q 'this copy:' <<< "$output"; then
        echo "error: setup information is missing" >&2
        exit 1
    fi
    echo "smoke test passed"
}

install_app() {
    local output
    output="$(mktemp -d "$PWD/build/installer.XXXXXX")"
    python3 scripts/make_installer.py --app "$APP" --output "$output"
    open "$output/Install FlickOff.app"
    echo "Installer opened. Choose Agree and Install to complete installation."
}

case "${1:-}" in
    test) run_tests ;;
    install) run_tests; build_app; smoke_test "$APP"; install_app ;;
    "") run_tests; build_app; smoke_test "$APP"; self_test "$APP" ;;
    *) echo "usage: $0 [test|install]" >&2; exit 2 ;;
esac
