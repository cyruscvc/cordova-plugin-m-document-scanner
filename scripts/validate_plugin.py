#!/usr/bin/env python3
"""Validate this Cordova plugin as an OutSystems local Resource source or ZIP."""

from __future__ import annotations

import argparse
import json
import re
import stat
import sys
import zipfile
from pathlib import Path, PurePosixPath
from xml.etree import ElementTree as ET


ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$")
LOCAL_FILE_TAGS = {"js-module", "source-file", "header-file", "resource-file", "hook"}


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


class PluginView:
    def __init__(self, source: Path):
        self.source = source
        self.archive: zipfile.ZipFile | None = None
        self.members: set[str] = set()
        self.root = source.name

        if source.is_file() and source.suffix.lower() == ".zip":
            self.archive = zipfile.ZipFile(source)
            roots: set[str] = set()
            for info in self.archive.infolist():
                name = info.filename.replace("\\", "/").rstrip("/")
                if not name:
                    continue
                path = PurePosixPath(name)
                if path.is_absolute() or ".." in path.parts:
                    raise ValueError(f"Unsafe archive path: {name}")
                if stat.S_ISLNK(info.external_attr >> 16):
                    raise ValueError(f"Archive contains a symlink: {name}")
                roots.add(path.parts[0])
                self.members.add(name)
            if len(roots) != 1:
                raise ValueError(f"ZIP must contain exactly one root; found {sorted(roots)}")
            self.root = next(iter(roots))
        elif not source.is_dir():
            raise ValueError("Input must be a plugin directory or ZIP")

    def close(self) -> None:
        if self.archive:
            self.archive.close()

    def exists(self, relative: str) -> bool:
        if self.archive:
            return f"{self.root}/{relative.strip('/')}" in self.members
        return (self.source / relative).is_file()

    def read(self, relative: str) -> bytes:
        if self.archive:
            return self.archive.read(f"{self.root}/{relative.strip('/')}")
        return (self.source / relative).read_bytes()


def validate(source: Path) -> tuple[list[str], list[str], str | None]:
    errors: list[str] = []
    warnings: list[str] = []
    try:
        view = PluginView(source)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        return [str(error)], warnings, None

    try:
        for required in ("plugin.xml", "package.json"):
            if not view.exists(required):
                errors.append(f"Missing {required} directly under package root")
        if errors:
            return errors, warnings, None

        try:
            package = json.loads(view.read("package.json").decode("utf-8"))
            xml = ET.fromstring(view.read("plugin.xml"))
        except (UnicodeDecodeError, json.JSONDecodeError, ET.ParseError) as error:
            return [f"Invalid metadata: {error}"], warnings, None

        plugin_id = (xml.attrib.get("id") or "").strip()
        xml_version = (xml.attrib.get("version") or "").strip()
        package_name = str(package.get("name") or "").strip()
        package_version = str(package.get("version") or "").strip()
        cordova = package.get("cordova") if isinstance(package.get("cordova"), dict) else {}
        cordova_id = str(cordova.get("id") or "").strip()

        if not ID_RE.fullmatch(plugin_id) or not plugin_id.startswith("cordova-plugin-"):
            errors.append(f"Invalid MABS-safe Cordova ID: {plugin_id!r}")
        if len({plugin_id, package_name, cordova_id}) != 1:
            errors.append("plugin.xml id, package.json name, and cordova.id must match")
        if xml_version != package_version or not SEMVER_RE.fullmatch(xml_version):
            errors.append("plugin.xml and package.json must use the same semantic version")
        if view.root != plugin_id:
            errors.append(f"Package root {view.root!r} must match {plugin_id!r}")
        if source.is_file() and source.stem != plugin_id:
            errors.append(f"ZIP filename must be {plugin_id}.zip")

        xml_platforms = sorted({
            element.attrib["name"]
            for element in xml.iter()
            if local_name(element.tag) == "platform" and element.attrib.get("name")
        })
        package_platforms = sorted(set(cordova.get("platforms") or []))
        if xml_platforms != package_platforms:
            errors.append(
                f"Platform mismatch: plugin.xml={xml_platforms}, package.json={package_platforms}"
            )

        for element in xml.iter():
            if local_name(element.tag) not in LOCAL_FILE_TAGS:
                continue
            referenced = element.attrib.get("src")
            if referenced and not view.exists(referenced):
                errors.append(f"plugin.xml references missing file: {referenced}")

        if source.is_file() and view.archive:
            for name in view.members:
                parts = PurePosixPath(name).parts
                if any(part in {".git", "node_modules", "__MACOSX"} for part in parts):
                    warnings.append(f"Development content should not be packaged: {name}")
                if name.endswith(".DS_Store") or (len(parts) > 1 and name.endswith(".zip")):
                    warnings.append(f"Archive hygiene issue: {name}")
        return errors, warnings, plugin_id or None
    finally:
        view.close()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", type=Path)
    args = parser.parse_args()
    source = args.plugin.resolve()
    errors, warnings, plugin_id = validate(source)
    print(f"Validating: {source}")
    if plugin_id:
        print(f"Plugin ID: {plugin_id}")
    for warning in warnings:
        print(f"WARNING: {warning}")
    for error in errors:
        print(f"ERROR: {error}")
    print("RESULT: VALID" if not errors else "RESULT: INVALID")
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
