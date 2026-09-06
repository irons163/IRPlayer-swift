#!/usr/bin/env bash

set -euo pipefail

mode="${1:-all}"
case "$mode" in
    framework | transport | ui | package | sanitizer | all) ;;
    *)
        echo "Usage: $0 [framework|transport|ui|package|sanitizer|all]" >&2
        exit 2
        ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/../.." && pwd)"
cd "$repository_root"

if [[ -n "${IRPLAYER_RESULT_DIR:-}" ]]; then
    result_directory="$IRPLAYER_RESULT_DIR"
    mkdir -p "$result_directory"
else
    result_directory="$(mktemp -d "${TMPDIR:-/tmp}/irplayer-acceptance.XXXXXX")"
fi

derived_data_directory="${IRPLAYER_DERIVED_DATA_DIR:-$result_directory/DerivedData}"
mkdir -p "$derived_data_directory"

simulator_id="$("$script_dir/select-ios-simulator.sh")"

{
    printf 'Repository: %s\n' "$repository_root"
    printf 'Mode: %s\n' "$mode"
    printf 'Simulator: %s\n' "$simulator_id"
    printf 'Commit: %s\n' "$(git rev-parse HEAD)"
    xcodebuild -version
    swift --version
    sw_vers
} | tee "$result_directory/environment.txt"

run_xcodebuild() {
    local log_path="$1"
    shift
    NSUnbufferedIO=YES xcodebuild "$@" 2>&1 | tee "$log_path"
}

prepare_simulator() {
    xcrun simctl boot "$simulator_id" 2>/dev/null || true
    xcrun simctl bootstatus "$simulator_id" -b
}

run_transport_acceptance() {
    local probe_directory="$repository_root/Scripts/dependencies/tests/ios_tls_probe"
    local packaged_libraries="$repository_root/Sources/IRPlayer-swift/ThirdParty/IRFFMpeg/Libs"
    local regression
    prepare_simulator
    # Validate the binaries actually shipped by the SDK, never a temporary
    # build stage supplied through the developer's environment.
    python3 "$probe_directory/run_tls13_regression.py" \
        --stage "$packaged_libraries" --device "$simulator_id" \
        --verification default \
        2>&1 | tee "$result_directory/transport-tls13.log"
    for regression in http hls reconnect deadline cookie; do
        python3 "$probe_directory/run_${regression}_regression.py" \
            --stage "$packaged_libraries" --device "$simulator_id" \
            2>&1 | tee "$result_directory/transport-${regression}.log"
    done
}

run_framework_acceptance() {
    local device_build_log="$result_directory/framework-device-build.log"
    local test_log="$result_directory/framework-tests.log"
    local result_bundle="$result_directory/framework-tests.xcresult"

    if [[ -e "$result_bundle" ]]; then
        echo "Result bundle already exists: $result_bundle" >&2
        exit 1
    fi

    git diff --check
    swift package dump-package >/dev/null

    run_xcodebuild "$device_build_log" \
        -project IRPlayer-swift.xcodeproj \
        -scheme IRPlayer-swift \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -derivedDataPath "$derived_data_directory/framework-device" \
        CODE_SIGNING_ALLOWED=NO \
        build

    prepare_simulator
    run_xcodebuild "$test_log" \
        test \
        -project IRPlayer-swift.xcodeproj \
        -scheme IRPlayer-swift \
        -destination "platform=iOS Simulator,id=$simulator_id" \
        -derivedDataPath "$derived_data_directory/framework-tests" \
        -resultBundlePath "$result_bundle" \
        -parallel-testing-enabled NO
    run_transport_acceptance
}

run_ui_acceptance() {
    local test_log="$result_directory/playback-ui-tests.log"
    local result_bundle="$result_directory/playback-ui-tests.xcresult"

    if [[ -e "$result_bundle" ]]; then
        echo "Result bundle already exists: $result_bundle" >&2
        exit 1
    fi

    prepare_simulator
    run_xcodebuild "$test_log" \
        test \
        -project SPMDemo/SPMDemo.xcodeproj \
        -scheme SPMDemo \
        -destination "platform=iOS Simulator,id=$simulator_id" \
        -derivedDataPath "$derived_data_directory/playback-ui-tests" \
        -resultBundlePath "$result_bundle" \
        -parallel-testing-enabled NO \
        -only-testing:SPMDemoUITests/SPMDemoUITests
}

run_package_acceptance() {
    swift build \
        --scratch-path "$derived_data_directory/package-device" \
        --triple arm64-apple-ios15.0 \
        --sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
        2>&1 | tee "$result_directory/package-device-build.log"

    swift build --build-tests \
        --scratch-path "$derived_data_directory/package-simulator" \
        --triple arm64-apple-ios15.0-simulator \
        --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
        2>&1 | tee "$result_directory/package-test-build.log"

    run_xcodebuild "$result_directory/sdk-documentation.log" \
        docbuild \
        -project IRPlayer-swift.xcodeproj \
        -scheme IRPlayer-swift \
        -destination "generic/platform=iOS" \
        -derivedDataPath "$derived_data_directory/documentation" \
        CODE_SIGNING_ALLOWED=NO \
        OTHER_DOCC_FLAGS="--warnings-as-errors"
}

run_sanitizer_acceptance() {
    local result_bundle="$result_directory/framework-tsan.xcresult"
    if [[ -e "$result_bundle" ]]; then
        echo "Result bundle already exists: $result_bundle" >&2
        exit 1
    fi
    prepare_simulator
    run_xcodebuild "$result_directory/framework-tsan.log" \
        test \
        -project IRPlayer-swift.xcodeproj \
        -scheme IRPlayer-swift \
        -destination "platform=iOS Simulator,id=$simulator_id" \
        -derivedDataPath "$derived_data_directory/framework-tsan" \
        -resultBundlePath "$result_bundle" \
        -parallel-testing-enabled NO \
        -enableThreadSanitizer YES
}

case "$mode" in
    framework)
        run_framework_acceptance
        ;;
    transport)
        run_transport_acceptance
        ;;
    ui)
        run_ui_acceptance
        ;;
    package)
        run_package_acceptance
        ;;
    sanitizer)
        run_sanitizer_acceptance
        ;;
    all)
        run_framework_acceptance
        run_ui_acceptance
        run_package_acceptance
        run_sanitizer_acceptance
        ;;
esac

printf 'Acceptance mode "%s" passed. Results: %s\n' "$mode" "$result_directory"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        printf '## IRPlayer acceptance passed\n\n'
        printf -- '- Mode: `%s`\n' "$mode"
        printf -- '- Simulator: `%s`\n' "$simulator_id"
        printf -- '- Commit: `%s`\n' "$(git rev-parse HEAD)"
    } >>"$GITHUB_STEP_SUMMARY"
fi
