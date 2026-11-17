#!/usr/bin/env python3
"""Render the skeleton into a new package directory.

    python scripts/render.py --package-name my-lib --description "..." \
        --owner group:default/team-a --python-version 3.12 --out ./my-lib

Stdlib only, so the Argo step can run it in any Python image. Substitutes
{{package_name}}, {{description}}, {{owner}}, {{python_version}} and the derived
{{module_name}} (package name with - and . turned into _), and renames
src/__module_name__ to src/<module_name>.
"""

import argparse
import re
import shutil
import sys
from pathlib import Path

# PEP 508 distribution name.
NAME_RE = re.compile(r"^([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9])$")
VERSION_RE = re.compile(r"^3\.\d{1,2}$")
SKELETON = Path(__file__).resolve().parent.parent / "python-skeleton"


def escape_quoted(value: str) -> str:
    """Safe inside a double-quoted TOML or YAML string."""
    return value.replace("\\", "\\\\").replace('"', '\\"')


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--package-name", required=True)
    p.add_argument("--description", required=True)
    p.add_argument("--owner", required=True)
    p.add_argument("--python-version", required=True)
    p.add_argument("--out", required=True, type=Path)
    a = p.parse_args()

    if not NAME_RE.match(a.package_name):
        sys.exit(f"error: package_name {a.package_name!r} is not a valid PEP 508 name")
    if not VERSION_RE.match(a.python_version):
        sys.exit(f"error: python_version {a.python_version!r} must look like 3.12")
    if "\n" in a.description or "\n" in a.owner:
        sys.exit("error: description and owner must be a single line")
    if a.out.exists() and any(a.out.iterdir()):
        sys.exit(f"error: {a.out} already exists and is not empty")

    module_name = re.sub(r"[-.]+", "_", a.package_name).lower()
    values = {
        "{{package_name}}": a.package_name,
        "{{module_name}}": module_name,
        "{{description}}": escape_quoted(a.description),
        "{{owner}}": a.owner,
        "{{python_version}}": a.python_version,
    }

    shutil.copytree(SKELETON, a.out, dirs_exist_ok=True)
    (a.out / "src" / "__module_name__").rename(a.out / "src" / module_name)

    for path in a.out.rglob("*"):
        if not path.is_file() or path.suffix == ".typed":
            continue
        text = path.read_text()
        for key, value in values.items():
            text = text.replace(key, value)
        path.write_text(text)

    placeholder = re.compile(r"\{\{(package_name|module_name|description|owner|python_version)\}\}")
    leftover = [
        str(f) for f in a.out.rglob("*") if f.is_file() and placeholder.search(f.read_text())
    ]
    if leftover:
        sys.exit(f"error: unreplaced placeholders in {leftover}")
    print(f"rendered {a.package_name} (module {module_name}) into {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
