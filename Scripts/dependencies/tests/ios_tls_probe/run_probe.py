#!/usr/bin/env python3
"""Build and run the FFmpeg AVIO/demux TLS probe in a booted iOS Simulator."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def checked(command: list[str], *, capture: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, check=True, text=True, capture_output=capture)


def xcrun(*arguments: str, capture: bool = True) -> str:
    result = checked(["xcrun", *arguments], capture=capture)
    return result.stdout.strip() if capture else ""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def assert_simulator_library(library: Path) -> dict[str, str]:
    description = checked(["file", "-L", str(library)], capture=True).stdout
    if "arm64" not in description or "dynamically linked shared library" not in description:
        raise RuntimeError(f"unexpected simulator library: {description.strip()}")
    build = xcrun("vtool", "-arch", "arm64", "-show-build", str(library))
    if "platform IOSSIMULATOR" not in build:
        raise RuntimeError(f"library is not built for iOS Simulator: {library}\n{build}")
    return {"path": str(library.resolve()), "sha256": sha256(library)}


def simulator_framework(bundle: Path, name: str) -> Path:
    with (bundle / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    matches = [
        entry for entry in info.get("AvailableLibraries", [])
        if entry.get("SupportedPlatform") == "ios"
        and entry.get("SupportedPlatformVariant") == "simulator"
        and "arm64" in entry.get("SupportedArchitectures", [])
    ]
    if len(matches) != 1:
        raise RuntimeError(f"expected one arm64 simulator slice in {bundle}")
    entry = matches[0]
    framework = (bundle / entry["LibraryIdentifier"] / entry["LibraryPath"]).resolve()
    if not framework.is_relative_to(bundle.resolve()) or framework.name != f"{name}.framework":
        raise RuntimeError(f"invalid framework path in {bundle}: {framework}")
    if not (framework / "Headers").is_dir() or not (framework / name).is_file():
        raise RuntimeError(f"framework headers or binary are missing: {framework}")
    return framework


def assert_candidate(stage: Path) -> tuple[Path, Path, list[dict[str, str]]]:
    ffmpeg = stage / "ffmpeg"
    include = ffmpeg / "include"
    libraries = ffmpeg / "lib"
    required = [
        include / "libavformat" / "avio.h",
        include / "libavutil" / "dict.h",
        libraries / "libavformat.dylib",
        libraries / "libavutil.dylib",
    ]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise RuntimeError("candidate simulator artifacts are missing: " + ", ".join(missing))
    manifest = []
    resolved_libraries = sorted({library.resolve() for library in libraries.glob("*.dylib")})
    for library in resolved_libraries:
        manifest.append(assert_simulator_library(library))
    return include, libraries, manifest


def prepare_candidate(stage: Path, workdir: Path) -> tuple[list[str], list[dict[str, str]]]:
    if (stage / "libavformat.xcframework").is_dir():
        # Consume the same five binary targets as the SDK, without changing
        # their install names or modifying the repository's distribution.
        frameworks = workdir / "Frameworks"
        frameworks.mkdir()
        manifest = []
        for name in ("libavformat", "libavcodec", "libavutil", "libswresample", "libswscale"):
            framework = simulator_framework(stage / f"{name}.xcframework", name)
            manifest.append(assert_simulator_library(framework / name))
            shutil.copytree(framework, frameworks / framework.name, symlinks=True)
        return [
            "-F", str(frameworks),
            "-framework", "libavformat", "-framework", "libavcodec",
            "-framework", "libavutil", "-Wl,-rpath,@executable_path/Frameworks",
        ], manifest
    include, libraries, manifest = assert_candidate(stage)
    copy_runtime_libraries(libraries, workdir / "lib")
    return [
        "-I", str(include), "-L", str(libraries),
        "-lavformat", "-lavcodec", "-lavutil", "-Wl,-rpath,@executable_path/lib",
    ], manifest


def compile_probe(source: Path, link_arguments: list[str], output: Path) -> None:
    sdk = xcrun("--sdk", "iphonesimulator", "--show-sdk-path")
    clang = xcrun("--sdk", "iphonesimulator", "--find", "clang")
    checked([
        clang,
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-target",
        "arm64-apple-ios15.0-simulator",
        "-isysroot",
        sdk,
        str(source),
        *link_arguments,
        "-o",
        str(output),
    ])


def copy_runtime_libraries(source: Path, destination: Path) -> None:
    destination.mkdir()
    for entry in source.iterdir():
        if entry.name.endswith(".dylib"):
            target = destination / entry.name
            if entry.is_symlink():
                target.symlink_to(os.readlink(entry))
            else:
                shutil.copy2(entry, target)


def booted_device(device: str) -> str:
    if device != "booted":
        return device
    devices = json.loads(xcrun("simctl", "list", "devices", "booted", "--json"))
    for runtime_devices in devices.get("devices", {}).values():
        for candidate in runtime_devices:
            if candidate.get("state") == "Booted":
                return candidate["udid"]
    raise RuntimeError("no booted iOS Simulator is available")


def decoded(output: str | bytes) -> str:
    if isinstance(output, bytes):
        return output.decode("utf-8", errors="replace")
    return output


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    environment_stage = os.environ.get("IRPLAYER_FFMPEG_SIM_STAGE")
    parser.add_argument(
        "--stage", type=Path,
        default=Path(environment_stage) if environment_stage else None,
        help="raw candidate stage or XCFramework directory (or set IRPLAYER_FFMPEG_SIM_STAGE)",
    )
    parser.add_argument("--device", default="booted")
    parser.add_argument("--ca-file", type=Path)
    parser.add_argument("--deadline-ms", type=int, default=5000)
    parser.add_argument("--read-bytes", type=int, default=1)
    parser.add_argument("--read-iterations", type=int, default=1)
    parser.add_argument("--max-packets", type=int, default=8)
    parser.add_argument("--headers")
    parser.add_argument("--reconnect", action="store_true")
    parser.add_argument("--reconnect-streamed", action="store_true")
    parser.add_argument("--http-persistent", choices=("0", "1"))
    parser.add_argument("--http-multiple", choices=("0", "1"))
    parser.add_argument(
        "--allow-http-root", action="store_true",
        help="allow an HTTP root URL for controlled nested-HTTPS policy tests",
    )
    parser.add_argument("--operation", choices=("avio", "demux"), default="avio")
    parser.add_argument("--verification", choices=("forced", "default"),
                        default="forced")
    parser.add_argument("--expect", choices=("success", "failure", "timeout"))
    parser.add_argument("--keep-workdir", action="store_true")
    args = parser.parse_args()
    if args.stage is None:
        parser.error("--stage or IRPLAYER_FFMPEG_SIM_STAGE is required")
    if (args.deadline_ms <= 0 or args.read_bytes <= 0 or
            args.read_iterations <= 0 or args.max_packets <= 0):
        parser.error("deadline, read size/iterations, and packet limit must be positive")
    if args.ca_file and not args.ca_file.is_file():
        parser.error(f"CA file does not exist: {args.ca_file}")

    source = Path(__file__).with_name("probe.c")
    workdir = Path(tempfile.mkdtemp(prefix="irplayer-ios-tls-probe-"))
    executable = workdir / "irplayer-ios-tls-probe"
    try:
        link_arguments, manifest = prepare_candidate(args.stage, workdir)
        compile_probe(source, link_arguments, executable)
    except Exception:
        if not args.keep_workdir:
            shutil.rmtree(workdir)
        raise

    command = [
        "xcrun", "simctl", "spawn", booted_device(args.device),
        str(executable), args.url,
        "--deadline-ms", str(args.deadline_ms),
        "--read-bytes", str(args.read_bytes),
        "--read-iterations", str(args.read_iterations),
        "--max-packets", str(args.max_packets),
        "--operation", args.operation,
        "--verification", args.verification,
    ]
    if args.headers:
        command += ["--headers", args.headers]
    if args.reconnect:
        command += ["--reconnect"]
    if args.reconnect_streamed:
        command += ["--reconnect-streamed"]
    if args.http_persistent is not None:
        command += ["--http-persistent", args.http_persistent]
    if args.http_multiple is not None:
        command += ["--http-multiple", args.http_multiple]
    if args.allow_http_root:
        command += ["--allow-http-root"]
    if args.ca_file:
        copied_ca = workdir / "explicit-ca.pem"
        shutil.copy2(args.ca_file, copied_ca)
        command += ["--ca-file", str(copied_ca)]
    print("candidate_manifest=" + json.dumps(manifest, sort_keys=True))
    host_timeout = args.deadline_ms / 1000 + 10
    try:
        result = subprocess.run(
            command, text=True, capture_output=True, timeout=host_timeout
        )
    except subprocess.TimeoutExpired as error:
        if error.stdout:
            sys.stdout.write(decoded(error.stdout))
        if error.stderr:
            sys.stderr.write(decoded(error.stderr))
        print(f"host_watchdog_timeout_seconds={host_timeout}")
        print(f"probe_workdir={workdir}")
        if not args.keep_workdir:
            shutil.rmtree(workdir)
        return 124
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    print(f"simulator_process_returncode={result.returncode}")
    print(f"probe_workdir={workdir}")

    matched = (
        (args.expect == "success" and result.returncode == 0)
        or (args.expect == "failure" and result.returncode == 10)
        or (args.expect == "timeout" and result.returncode == 11)
    )
    if not args.keep_workdir:
        shutil.rmtree(workdir)
    if args.expect is None:
        return result.returncode
    if not matched:
        print(
            f"probe_expectation_failed: expected={args.expect} "
            f"simulator_process_returncode={result.returncode}",
            file=sys.stderr,
        )
    return 0 if matched else 1


if __name__ == "__main__":
    raise SystemExit(main())
