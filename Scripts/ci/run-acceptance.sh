#!/usr/bin/env bash

set -euo pipefail

mode="${1:-all}"
case "$mode" in
    framework | ui | all) ;;
    *)
        echo "Usage: $0 [framework|ui|all]" >&2
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

case "$mode" in
    framework)
        run_framework_acceptance
        ;;
    ui)
        run_ui_acceptance
        ;;
    all)
        run_framework_acceptance
        run_ui_acceptance
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
