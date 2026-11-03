#!/bin/bash
# Builds FlickOff.app from the Swift package.
#   ./build.sh            unit tests, release build -> build/FlickOff.app, self-test
#   ./build.sh test       unit tests only (hardware tests: TB_HARDWARE_TESTS=1 ./build.sh test)
#   ./build.sh install    unit tests, build, copy to /Applications, self-test, relaunch
set -euo pipefail
cd "$(dirname "$0")"

APP=build/FlickOff.app
ARCH="${TB_BUILD_ARCH:-arm64}"
case "$ARCH" in
    arm64|x86_64) ;;
    *) echo "error: TB_BUILD_ARCH must be arm64 or x86_64" >&2; exit 2 ;;
esac
# Intel bundles are disposable CI smoke checks, never local release candidates.
if [[ "$ARCH" == x86_64 && ( "${CI:-}" != true || "$(uname -m)" != x86_64 ) ]]; then
    echo "error: Intel test bundles require native Intel CI; local builds must use arm64" >&2
    exit 2
fi

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
    if [[ "$ARCH" == x86_64 ]]; then
        /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier io.github.ZheMaxy.FlickOff.BuildCheck' "$APP/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Set :CFBundleName FlickOff Build Check' "$APP/Contents/Info.plist"
        /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName FlickOff Build Check' "$APP/Contents/Info.plist"
    fi
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
    local stage
    stage="$(mktemp -d /Applications/.FlickOff.XXXXXX)"
    if ! ditto "$APP" "$stage/FlickOff.app"; then
        rm -rf "$stage"
        return 1
    fi
    pkill -x FlickOff 2>/dev/null && sleep 1 || true
    rm -rf /Applications/FlickOff.app
    mv "$stage/FlickOff.app" /Applications/
    rmdir "$stage"
    self_test /Applications/FlickOff.app
    open /Applications/FlickOff.app
    echo "installed /Applications/FlickOff.app"
}

case "${1:-}" in
    test) run_tests ;;
    install) run_tests; build_app; smoke_test "$APP"; install_app ;;
    "") run_tests; build_app; smoke_test "$APP"; self_test "$APP" ;;
    *) echo "usage: $0 [test|install]" >&2; exit 2 ;;
esac
