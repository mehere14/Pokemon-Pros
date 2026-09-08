#!/usr/bin/env python3

from __future__ import annotations

import contextlib
import io
from pathlib import Path
import tempfile
import unittest

import terminology_compliance as gate


def word(*scalars: int) -> str:
    return "".join(chr(value) for value in scalars)


class TerminologyComplianceTests(unittest.TestCase):
    def test_reports_exact_relative_file_and_line(self) -> None:
        prohibited = word(112, 111, 107, 101, 109, 111, 110)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = root / "Fixtures" / "sample.json"
            fixture.parent.mkdir()
            fixture.write_text(f'{{\n  "name": "{prohibited}"\n}}\n', encoding="utf-8")

            self.assertEqual(
                gate.scan_source(root),
                ["Fixtures/sample.json:2: prohibited terminology"],
            )

    def test_detects_accented_and_unaccented_forms_case_insensitively(self) -> None:
        plain_upper = word(80, 79, 75, 69, 77, 79, 78)
        accented_mixed = word(80, 111, 75, 201, 109, 79, 110)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = root / "Cases.swift"
            fixture.write_text(f"{plain_upper}\n{accented_mixed}\n", encoding="utf-8")

            self.assertEqual(
                gate.scan_source(root),
                [
                    "Cases.swift:1: prohibited terminology",
                    "Cases.swift:2: prohibited terminology",
                ],
            )

    def test_ignores_unrelated_partial_character_sequences(self) -> None:
        fragments = [
            word(112, 111, 107, 101),
            word(109, 111, 110),
            word(115, 112, 111, 107, 101, 32, 109, 111, 110, 105, 116, 111, 114),
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "Neutral.strings").write_text("\n".join(fragments), encoding="utf-8")
            self.assertEqual(gate.scan_source(root), [])

    def test_only_plan_and_design_reference_are_excluded(self) -> None:
        prohibited = word(112, 111, 107, 101, 109, 111, 110)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for folder in ("Plan", "Design Mockup", "Reference"):
                path = root / folder / "fixture.json"
                path.parent.mkdir()
                path.write_text(prohibited, encoding="utf-8")

            self.assertEqual(
                gate.scan_source(root),
                ["Reference/fixture.json:1: prohibited terminology"],
            )

    def test_detects_prohibited_source_and_asset_names(self) -> None:
        prohibited = word(112, 111, 107, 101, 109, 111, 110)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / f"{prohibited}Client.swift"
            asset = root / "Images.xcassets" / f"{prohibited}.imageset" / "Contents.json"
            source.write_text("struct NeutralClient {}\n", encoding="utf-8")
            asset.parent.mkdir(parents=True)
            asset.write_text("{}\n", encoding="utf-8")

            self.assertEqual(
                gate.scan_source(root),
                [
                    f"Images.xcassets/{prohibited}.imageset/Contents.json:0: prohibited terminology in path",
                    f"{prohibited}Client.swift:0: prohibited terminology in path",
                ],
            )

    def test_cli_returns_failure_then_passes_after_fixture_removal(self) -> None:
        prohibited = word(112, 111, 107, 233, 109, 111, 110)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = root / "Disposable.json"
            fixture.write_text(prohibited, encoding="utf-8")
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(gate.main(["source", "--root", str(root)]), 1)
            fixture.unlink()
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(gate.main(["source", "--root", str(root)]), 0)


if __name__ == "__main__":
    unittest.main()
