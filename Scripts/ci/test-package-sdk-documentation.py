#!/usr/bin/env python3
"""Regression tests for the SDK DocC archive packaging helper."""

from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest


HELPER = Path(__file__).with_name("package-sdk-documentation.sh")


class PackageSDKDocumentationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="irplayer-sdk-docs ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.products = self.root / "Products with spaces"
        self.products.mkdir()
        self.output = self.root / "SDK documentation.tar.gz"

    def run_helper(self, *arguments: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(HELPER), *(str(argument) for argument in arguments)],
            capture_output=True,
            text=True,
            timeout=10,
        )

    def make_archive(self, relative_path: str, files: dict[str, bytes]) -> dict[str, bytes]:
        archive = self.products / relative_path
        archive.mkdir(parents=True)
        for relative_file, contents in files.items():
            path = archive / relative_file
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(contents)
        return {
            (Path(relative_path) / relative_file).as_posix(): contents
            for relative_file, contents in files.items()
        }

    @staticmethod
    def tree_snapshot(root: Path) -> list[tuple[str, str, bytes | None]]:
        snapshot = []
        for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
            relative = path.relative_to(root).as_posix()
            if path.is_dir():
                snapshot.append((relative, "directory", None))
            else:
                snapshot.append((relative, "file", path.read_bytes()))
        return snapshot

    def assert_success(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertEqual(
            result.returncode,
            0,
            f"helper failed with status {result.returncode}:\n"
            f"stdout={result.stdout}\nstderr={result.stderr}",
        )

    def assert_failure(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertNotEqual(
            result.returncode,
            0,
            f"helper unexpectedly succeeded:\nstdout={result.stdout}\nstderr={result.stderr}",
        )

    def assert_archive_contains(self, expected_files: dict[str, bytes]) -> None:
        with tarfile.open(self.output, mode="r:gz") as archive:
            # GNU and BSD tar commonly retain the harmless ``./`` prefix from
            # find output. Normalize it while checking the paths themselves.
            members = {
                member.name.removeprefix("./"): member for member in archive.getmembers()
            }
            file_names = {name for name, member in members.items() if member.isfile()}
            self.assertEqual(file_names, set(expected_files))
            for name, contents in expected_files.items():
                with self.subTest(member=name):
                    self.assertIn(name, members)
                    self.assertTrue(members[name].isfile())
                    extracted = archive.extractfile(members[name])
                    self.assertIsNotNone(extracted)
                    self.assertEqual(extracted.read(), contents)

            for name in members:
                with self.subTest(member=name):
                    self.assertFalse(name.startswith("/"))
                    self.assertNotIn("..", Path(name).parts)

    def test_nested_multiple_archives_preserve_relative_paths(self) -> None:
        expected = {}
        expected.update(
            self.make_archive(
                "Debug-iphoneos/IRPlayer.doccarchive",
                {
                    "data/documentation/IRPlayer/index.json": b"debug index\n",
                    "data/documentation/IRPlayer/overview.md": b"debug overview\n",
                },
            )
        )
        expected.update(
            self.make_archive(
                "Nested/Release/SDK Docs.doccarchive",
                {
                    "data/documentation/SDK Docs/index.json": b"release index\n",
                    "data/documentation/SDK Docs/tutorial.md": b"release tutorial\n",
                },
            )
        )
        before = self.tree_snapshot(self.products)

        result = self.run_helper(self.products, self.output)

        self.assert_success(result)
        self.assert_archive_contains(expected)
        self.assertEqual(self.tree_snapshot(self.products), before)

    def test_colon_and_space_paths_round_trip(self) -> None:
        expected = self.make_archive(
            "Documentation for iOS/Feature Docs.doccarchive",
            {
                "data/documentation/Feature Docs/Type:method(arg:).json": b"symbol\n",
                "data/documentation/Feature Docs/Getting Started.md": b"guide\n",
            },
        )
        before = self.tree_snapshot(self.products)

        result = self.run_helper(self.products, self.output)

        self.assert_success(result)
        self.assert_archive_contains(expected)
        self.assertEqual(self.tree_snapshot(self.products), before)

    def test_missing_products_directory_fails(self) -> None:
        missing_products = self.root / "missing products"

        result = self.run_helper(missing_products, self.output)

        self.assert_failure(result)
        self.assertFalse(self.output.exists())

    def test_empty_products_directory_fails(self) -> None:
        (self.products / "not-a-doccarchive").mkdir()
        (self.products / "not-a-doccarchive" / "placeholder.txt").write_text("ignored\n")

        result = self.run_helper(self.products, self.output)

        self.assert_failure(result)
        self.assertFalse(self.output.exists())

    def test_existing_output_is_not_overwritten(self) -> None:
        self.make_archive("IRPlayer.doccarchive", {"index.json": b"index\n"})
        original_output = b"existing output must survive\n"
        self.output.write_bytes(original_output)

        result = self.run_helper(self.products, self.output)

        self.assert_failure(result)
        self.assertEqual(self.output.read_bytes(), original_output)

    def test_wrong_argument_count_fails(self) -> None:
        for arguments in ((), (self.products,), (self.products, self.output, self.root / "extra")):
            with self.subTest(arguments=arguments):
                result = self.run_helper(*arguments)
                self.assert_failure(result)


if __name__ == "__main__":
    unittest.main(verbosity=2)
