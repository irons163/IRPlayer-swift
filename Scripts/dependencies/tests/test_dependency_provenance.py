#!/usr/bin/env python3
"""Exercise the dependency provenance functions without building libraries.

The builder is loaded up to its explicit ``parse_arguments "$@"`` entry
point, so every provenance operation below is the implementation from
``build-ffmpeg-6.1.6.sh`` rather than a copy of it.  The loader only replaces
the three archive pins with hashes of tiny test archives; no repository file
or builder source is modified.
"""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


BUILDER = Path(__file__).resolve().parents[1] / "build-ffmpeg-6.1.6.sh"
MAIN_ENTRY = 'parse_arguments "$@"'
DEPENDENCIES = ("gmp", "nettle", "gnutls")
ARCHIVE_SUFFIXES = {"gmp": "tar.xz", "nettle": "tar.gz", "gnutls": "tar.xz"}


SHELL_SETUP = r'''
set -euo pipefail
source "$IRPLAYER_PROVENANCE_LOADER"

work_root="$IRPLAYER_PROVENANCE_ROOT"
target_name=fixture-target
target_triple=arm64-apple-darwin-fixture
gmp_host=aarch64-apple-darwin-fixture
sdk_name=fixture-sdk
sdk_path="$work_root/sdk"
clang_path="$(command -v cc)"
clangxx_path="$clang_path"
host_clang_path="$clang_path"
host_sdk_path="$sdk_path"
ar_path="$(command -v ar)"
ranlib_path="$(command -v ranlib)"
nm_path="$(command -v nm)"
platform_cflags='-target fixture-cflags'
platform_ldflags='-target fixture-ldflags'

fixture_version_for() {
    case "$1" in
        gmp) printf '%s\n' "$gmp_version" ;;
        nettle) printf '%s\n' "$nettle_version" ;;
        gnutls) printf '%s\n' "$gnutls_version" ;;
        *) return 1 ;;
    esac
}

fixture_source_for() {
    printf '%s/%s-%s\n' "$(vendor_dir)" "$1" "$(fixture_version_for "$1")"
}

fixture_archive_hash_for() {
    case "$1" in
        gmp) printf '%s\n' "$gmp_archive_sha256" ;;
        nettle) printf '%s\n' "$nettle_archive_sha256" ;;
        gnutls) printf '%s\n' "$gnutls_archive_sha256" ;;
        *) return 1 ;;
    esac
}

fixture_source_marker_for() {
    printf '%s/.%s-%s.extracted-source\n' \
        "$(vendor_dir)" "$1" "$(fixture_version_for "$1")"
}

fixture_output_for() {
    local dependency="$1"
    local prefix="$(dependency_prefix "$dependency")"
    case "$dependency" in
        gmp) printf '%s/lib/libgmp.a\n' "$prefix" ;;
        nettle) printf '%s/lib/libnettle.a\n' "$prefix" ;;
        gnutls) printf '%s/lib/libgnutls.a\n' "$prefix" ;;
        *) return 1 ;;
    esac
}

fixture_hogweed_output_for() {
    printf '%s/lib/libhogweed.a\n' "$(dependency_prefix nettle)"
}

record_fixture_fingerprint() {
    record_current_dependency_fingerprint "$1"
}

prepare_extracted_fixture() {
    local dependency="$1"
    assert_or_record_extracted_source \
        "$dependency" "$(fixture_version_for "$dependency")" \
        "$(fixture_archive_hash_for "$dependency")" \
        "$(fixture_source_for "$dependency")" yes
    assert_or_record_extracted_source \
        "$dependency" "$(fixture_version_for "$dependency")" \
        "$(fixture_archive_hash_for "$dependency")" \
        "$(fixture_source_for "$dependency")" no
}

'''


class DependencyProvenanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        builder_text = BUILDER.read_text(encoding="utf-8")
        if builder_text.count(MAIN_ENTRY) != 1:
            raise AssertionError("builder main entry marker must occur exactly once")
        cls.versions = {}
        for dependency in DEPENDENCIES:
            version_match = re.search(
                rf'^readonly {dependency}_version="([^"]+)"$',
                builder_text,
                re.MULTILINE,
            )
            if not version_match:
                raise AssertionError(f"builder {dependency} version pin is missing")
            cls.versions[dependency] = version_match.group(1)

        cls.archive_bytes = {
            dependency: f"IRPlayer {dependency} provenance fixture archive\n".encode()
            for dependency in DEPENDENCIES
        }
        cls.archive_hashes = {
            dependency: hashlib.sha256(content).hexdigest()
            for dependency, content in cls.archive_bytes.items()
        }
        loader_text = builder_text.split(MAIN_ENTRY, 1)[0]
        for dependency in DEPENDENCIES:
            loader_text, replacements = re.subn(
                rf'^readonly {dependency}_archive_sha256="[^"]*"$',
                f'readonly {dependency}_archive_sha256="{cls.archive_hashes[dependency]}"',
                loader_text,
                count=1,
                flags=re.MULTILINE,
            )
            if replacements != 1:
                raise AssertionError(f"builder {dependency} archive pin is missing")

        cls.loader_root = Path(
            tempfile.mkdtemp(prefix="irplayer-dependency-provenance-loader.", dir="/tmp")
        )
        cls.loader_path = cls.loader_root / "builder-functions.sh"
        cls.loader_path.write_text(loader_text, encoding="utf-8")
        cls.addClassCleanup(shutil.rmtree, cls.loader_root)

    def make_fixture(self) -> Path:
        root = Path(
            tempfile.mkdtemp(prefix="irplayer-ffmpeg-review.provenance.", dir="/tmp")
        )
        downloads = root / "downloads"
        sdk = root / "sdk"
        downloads.mkdir(parents=True)
        sdk.mkdir()
        for dependency in DEPENDENCIES:
            version = self.versions[dependency]
            (downloads / f"{dependency}-{version}.{ARCHIVE_SUFFIXES[dependency]}").write_bytes(
                self.archive_bytes[dependency]
            )
            source = root / "vendor" / f"{dependency}-{version}"
            source.mkdir(parents=True)
            if dependency == "gnutls":
                config_guess = source / "build-aux" / "config.guess"
                config_guess.parent.mkdir()
            else:
                config_guess = source / "config.guess"
            config_guess.write_text(
                "#!/bin/sh\nprintf '%s\\n' fixture-build\n", encoding="utf-8"
            )
            config_guess.chmod(0o755)
            (source / "payload.txt").write_text(
                f"{dependency} fixture source\n", encoding="utf-8"
            )
        for dependency, outputs in {
            "gmp": ("libgmp.a",),
            "nettle": ("libnettle.a", "libhogweed.a"),
            "gnutls": ("libgnutls.a",),
        }.items():
            output_dir = root / "stage" / "fixture-target" / dependency / "lib"
            output_dir.mkdir(parents=True)
            for output in outputs:
                (output_dir / output).write_bytes(
                    f"{dependency} fixture output {output}\n".encode()
                )
            include_dir = output_dir.parent / "include"
            include_dir.mkdir()
            (include_dir / "fixture.h").write_text("/* fixture header */\n")
            (include_dir / "alternate.h").write_text("/* alternate header */\n")
            (include_dir / "current.h").symlink_to("fixture.h")
            pkgconfig_dir = output_dir / "pkgconfig"
            pkgconfig_dir.mkdir()
            (pkgconfig_dir / f"{dependency}.pc").write_text(
                f"Name: {dependency}\nVersion: fixture\n"
            )
        (sdk / "SDKSettings.json").write_text(
            '{"DefaultProperties":{"SUPPORTED_PLATFORMS":[]}}\n', encoding="utf-8"
        )
        return root

    def run_case(
        self, body: str, expected: bool, expected_error: str | None = None
    ) -> subprocess.CompletedProcess[str]:
        root = self.make_fixture()
        try:
            environment = os.environ.copy()
            environment["IRPLAYER_PROVENANCE_LOADER"] = str(self.loader_path)
            environment["IRPLAYER_PROVENANCE_ROOT"] = str(root)
            result = subprocess.run(
                ["bash", "-c", SHELL_SETUP + "\n" + body, str(BUILDER)],
                check=False,
                capture_output=True,
                text=True,
                timeout=15,
                env=environment,
            )
            if expected:
                self.assertEqual(
                    result.returncode,
                    0,
                    f"stdout={result.stdout}\nstderr={result.stderr}",
                )
            else:
                self.assertNotEqual(
                    result.returncode,
                    0,
                    "negative provenance case unexpectedly passed",
                )
                if expected_error:
                    self.assertIn(expected_error, result.stderr)
            return result
        finally:
            shutil.rmtree(root)

    def test_valid_extraction_and_dependency_roundtrip(self) -> None:
        result = self.run_case(
            r'''
for dependency in gmp nettle gnutls; do
    prepare_extracted_fixture "$dependency"
    record_fixture_fingerprint "$dependency"
    assert_current_dependency_fingerprint "$dependency"
    marker_dir="$(dependency_prefix "$dependency")/.irplayer-build"
    test -s "$marker_dir/build-input.txt"
    test -s "$marker_dir/build-input.sha256"
    test -s "$marker_dir/output-sha256sums.txt"
    test -s "$work_root/metadata/slices/$target_name/dependencies/$dependency/build-input.txt"
done
''',
            expected=True,
        )
        self.assertEqual(result.stderr, "")

    def test_missing_dependency_markers_are_rejected(self) -> None:
        for marker in ("build-input.txt", "build-input.sha256", "output-sha256sums.txt"):
            with self.subTest(marker=marker):
                self.run_case(
                    f'''
record_fixture_fingerprint nettle
rm "$(dependency_prefix nettle)/.irplayer-build/{marker}"
assert_current_dependency_fingerprint nettle
''',
                    expected=False,
                    expected_error="no complete input/output fingerprint",
                )

    def test_target_change_is_rejected(self) -> None:
        self.run_case(
            r'''
record_fixture_fingerprint gnutls
target_triple=changed-target-triple
assert_current_dependency_fingerprint gnutls
''',
            expected=False,
            expected_error="inputs do not match",
        )

    def test_toolchain_flags_change_is_rejected(self) -> None:
        self.run_case(
            r'''
record_fixture_fingerprint gnutls
platform_cflags='-target changed-fixture-cflags'
assert_current_dependency_fingerprint gnutls
''',
            expected=False,
            expected_error="inputs do not match",
        )

    def test_output_change_is_rejected(self) -> None:
        self.run_case(
            r'''
record_fixture_fingerprint nettle
printf '%s\n' changed > "$(fixture_output_for nettle)"
assert_current_dependency_fingerprint nettle
''',
            expected=False,
            expected_error="outputs do not match",
        )

    def test_hogweed_output_change_is_rejected(self) -> None:
        self.run_case(
            r'''
record_fixture_fingerprint nettle
printf '%s\n' changed > "$(fixture_hogweed_output_for)"
assert_current_dependency_fingerprint nettle
''',
            expected=False,
            expected_error="outputs do not match",
        )

    def test_installed_header_and_pkgconfig_changes_are_rejected(self) -> None:
        for path in ("include/fixture.h", "lib/pkgconfig/gnutls.pc"):
            with self.subTest(path=path):
                self.run_case(
                    f'''
record_fixture_fingerprint gnutls
printf '%s\\n' changed >> "$(dependency_prefix gnutls)/{path}"
assert_current_dependency_fingerprint gnutls
''',
                    expected=False,
                    expected_error="outputs do not match",
                )

    def test_installed_symlink_retargeting_is_rejected(self) -> None:
        self.run_case(
            r'''
record_fixture_fingerprint gnutls
ln -sfn alternate.h "$(dependency_prefix gnutls)/include/current.h"
assert_current_dependency_fingerprint gnutls
''',
            expected=False,
            expected_error="outputs do not match",
        )

    def test_installed_file_addition_and_removal_are_rejected(self) -> None:
        for mutation in (
            'printf new > "$(dependency_prefix gnutls)/include/new.h"',
            'rm "$(dependency_prefix gnutls)/include/fixture.h"',
        ):
            with self.subTest(mutation=mutation):
                self.run_case(
                    f'''
record_fixture_fingerprint gnutls
{mutation}
assert_current_dependency_fingerprint gnutls
''',
                    expected=False,
                    expected_error="outputs do not match",
                )

    def test_missing_extracted_source_marker_is_rejected(self) -> None:
        self.run_case(
            r'''
prepare_extracted_fixture gnutls
rm "$(fixture_source_marker_for gnutls)"
assert_or_record_extracted_source gnutls "$gnutls_version" "$gnutls_archive_sha256" \
    "$(fixture_source_for gnutls)" no
''',
            expected=False,
            expected_error="no authenticated extraction marker",
        )

    def test_changed_extracted_source_is_rejected(self) -> None:
        self.run_case(
            r'''
prepare_extracted_fixture nettle
printf '%s\n' changed >> "$(fixture_source_for nettle)/payload.txt"
assert_or_record_extracted_source nettle "$nettle_version" "$nettle_archive_sha256" \
    "$(fixture_source_for nettle)" no
''',
            expected=False,
            expected_error="differs from the archive-derived tree",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
