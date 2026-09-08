#!/usr/bin/env python3
"""Enforce neutral terminology in shipping inputs and products."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import unicodedata


# Keep the prohibited words out of this scanner's own authored text.
_PROHIBITED_SCALARS = (
    (112, 111, 107, 101, 109, 111, 110),
    (112, 111, 107, 233, 109, 111, 110),
)
_PROHIBITED = tuple("".join(chr(value) for value in scalars) for scalars in _PROHIBITED_SCALARS)

_SOURCE_SUFFIXES = {
    ".c", ".cc", ".cpp", ".css", ".h", ".hh", ".hpp", ".html", ".js",
    ".jsx", ".m", ".mm", ".modulemap", ".sh", ".swift", ".ts", ".tsx",
}
_METADATA_SUFFIXES = {
    ".entitlements", ".json", ".pbxproj", ".plist", ".storyboard", ".xib",
    ".xcconfig", ".xcscheme",
}
_LOCALIZATION_SUFFIXES = {".strings", ".stringsdict", ".xcstrings"}
_SCANNED_SUFFIXES = _SOURCE_SUFFIXES | _METADATA_SUFFIXES | _LOCALIZATION_SUFFIXES
_EXCLUDED_TOP_LEVEL = {"Plan", "Design Mockup", "Loader"}


def _normalized(value: str) -> str:
    return unicodedata.normalize("NFC", value).casefold()


def _matched_term(value: str) -> str | None:
    normalized = _normalized(value)
    for term in _PROHIBITED:
        if _normalized(term) in normalized:
            return term
    return None


def _display_path(path: Path, root: Path | None) -> str:
    if root is not None:
        try:
            return path.resolve().relative_to(root.resolve()).as_posix()
        except ValueError:
            pass
    return path.as_posix()


def _scan_text(path: Path, root: Path | None) -> list[str]:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return []

    display_path = _display_path(path, root)
    violations: list[str] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        if _matched_term(line) is not None:
            violations.append(f"{display_path}:{line_number}: prohibited terminology")
    return violations


def _is_excluded(relative_path: Path) -> bool:
    return bool(relative_path.parts) and relative_path.parts[0] in _EXCLUDED_TOP_LEVEL


def scan_source(root: Path) -> list[str]:
    """Scan authored source/metadata and asset or localization path names."""
    violations: list[str] = []
    for directory, directory_names, file_names in os.walk(root):
        current = Path(directory)
        relative_directory = current.relative_to(root)
        directory_names[:] = sorted(
            name
            for name in directory_names
            if not _is_excluded(relative_directory / name)
        )

        for name in sorted(file_names):
            path = current / name
            relative_path = path.relative_to(root)
            if _is_excluded(relative_path):
                continue

            suffix = path.suffix.casefold()
            is_asset_path = any(part.casefold().endswith(".xcassets") for part in relative_path.parts)
            is_localized_path = any(part.casefold().endswith(".lproj") for part in relative_path.parts)
            if (suffix in _SCANNED_SUFFIXES or is_asset_path or is_localized_path) and _matched_term(relative_path.as_posix()) is not None:
                violations.append(
                    f"{relative_path.as_posix()}:0: prohibited terminology in path"
                )
            if suffix in _SCANNED_SUFFIXES or is_asset_path or is_localized_path:
                violations.extend(_scan_text(path, root))

    return sorted(set(violations))


def _scan_binary_strings(path: Path, root: Path | None) -> list[str]:
    try:
        result = subprocess.run(
            ["/usr/bin/strings", "-a", str(path)],
            check=False,
            capture_output=True,
            text=True,
            errors="replace",
        )
    except OSError:
        return []

    display_path = _display_path(path, root)
    return [
        f"{display_path}:strings:{line_number}: prohibited terminology"
        for line_number, line in enumerate(result.stdout.splitlines(), start=1)
        if _matched_term(line) is not None
    ]


def scan_product(path: Path) -> list[str]:
    """Scan every path, UTF-8 file, and binary string in a built product."""
    if not path.exists():
        return [f"{path.as_posix()}: missing product input"]

    root = path if path.is_dir() else path.parent
    candidates = sorted(item for item in path.rglob("*") if item.is_file()) if path.is_dir() else [path]
    violations: list[str] = []
    for candidate in candidates:
        display_path = _display_path(candidate, root)
        if _matched_term(display_path) is not None:
            violations.append(f"{display_path}:0: prohibited terminology in product path")
        text_violations = _scan_text(candidate, root)
        violations.extend(text_violations)
        if not text_violations:
            violations.extend(_scan_binary_strings(candidate, root))
    return sorted(set(violations))


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate neutral shipping terminology.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    source_parser = subparsers.add_parser("source", help="scan repository shipping inputs")
    source_parser.add_argument("--root", type=Path, default=Path.cwd())

    product_parser = subparsers.add_parser("product", help="scan a built bundle or executable")
    product_parser.add_argument("--path", type=Path, required=True)

    all_parser = subparsers.add_parser("all", help="scan source and optional built products")
    all_parser.add_argument("--root", type=Path, default=Path.cwd())
    all_parser.add_argument("--product", type=Path, action="append", default=[])
    return parser


def main(arguments: list[str] | None = None) -> int:
    options = _parser().parse_args(arguments)
    violations: list[str] = []
    if options.command in {"source", "all"}:
        root = options.root.resolve()
        violations.extend(scan_source(root))
    if options.command == "product":
        violations.extend(scan_product(options.path.resolve()))
    elif options.command == "all":
        for product in options.product:
            violations.extend(scan_product(product.resolve()))

    if violations:
        print("Terminology compliance failed:", file=sys.stderr)
        for violation in sorted(set(violations)):
            print(violation, file=sys.stderr)
        return 1

    print("Terminology compliance passed.")
    return 0



if __name__ == "__main__":
    raise SystemExit(main())
