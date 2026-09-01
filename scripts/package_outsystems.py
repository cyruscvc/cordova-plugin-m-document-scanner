#!/usr/bin/env python3
"""Create a deterministic single-root ZIP for an OutSystems local Resource."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import zipfile
from pathlib import Path

from validate_plugin import validate


EXCLUDED_DIRECTORIES = {
    ".git", ".github", "__pycache__", "build", "dist", "node_modules", "outsystems", "platforms", "plugins", "test"
}
EXCLUDED_FILES = {".DS_Store"}


def include(relative: Path) -> bool:
    if any(part in EXCLUDED_DIRECTORIES for part in relative.parts):
        return False
    if relative.name in EXCLUDED_FILES or relative.suffix.lower() == ".zip":
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    source = args.source.resolve()

    errors, warnings, plugin_id = validate(source)
    for warning in warnings:
        print(f"WARNING: {warning}")
    if errors or not plugin_id:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    output = (args.output or source.parent / f"{plugin_id}.zip").resolve()
    if output.name != f"{plugin_id}.zip":
        print(f"ERROR: Output filename must be {plugin_id}.zip", file=sys.stderr)
        return 1

    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        root = zipfile.ZipInfo(f"{plugin_id}/", date_time=(2020, 1, 1, 0, 0, 0))
        root.external_attr = 0o755 << 16
        archive.writestr(root, b"")
        for path in sorted(item for item in source.rglob("*") if item.is_file()):
            relative = path.relative_to(source)
            if not include(relative):
                continue
            info = zipfile.ZipInfo(
                f"{plugin_id}/{relative.as_posix()}",
                date_time=(2020, 1, 1, 0, 0, 0),
            )
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, path.read_bytes())

    packaged_errors, packaged_warnings, _ = validate(output)
    for warning in packaged_warnings:
        print(f"WARNING: {warning}")
    if packaged_errors:
        for error in packaged_errors:
            print(f"ERROR: {error}", file=sys.stderr)
        output.unlink(missing_ok=True)
        return 1

    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    print(f"Created: {output}")
    print(f"SHA-256: {digest}")
    print("Extensibility Configuration:")
    print(json.dumps({
        "resource": output.name,
        "plugin": {"resource": plugin_id}
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
