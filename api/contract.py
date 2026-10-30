"""
api.contract
============
The OpenAPI v1 document: authored as per-screen fragments, bundled into one
file the iOS build and the contract tests read.

``openapi/src/base.json`` holds the document skeleton and the shared
parameters, responses, and schemas; every other ``openapi/src/<screen>.json``
holds one screen's ``paths`` and its own ``components`` (names prefixed by the
screen, so fragments never collide).  ``openapi/v1.json`` is the bundle, the
single source of truth Swift types are generated from.  A test fails when the
bundle is stale; regenerate it with::

    python -m api.contract
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "openapi"
SOURCE_DIR = ROOT / "src"
BUNDLE_PATH = ROOT / "v1.json"
_COMPONENT_KINDS = ("schemas", "parameters", "responses")


def bundle() -> dict:
    """Merge every fragment into the base document; a duplicate path or
    component name is an error, never a silent overwrite."""
    doc = json.loads((SOURCE_DIR / "base.json").read_text())
    for path in sorted(SOURCE_DIR.glob("*.json")):
        if path.name == "base.json":
            continue
        fragment = json.loads(path.read_text())
        unknown = set(fragment) - {"paths", "components"}
        if unknown:
            raise ValueError(f"{path.name}: unexpected top-level keys {sorted(unknown)}")
        _merge(doc["paths"], fragment.get("paths", {}), f"{path.name} paths")
        components = fragment.get("components", {})
        for kind in components:
            if kind not in _COMPONENT_KINDS:
                raise ValueError(f"{path.name}: unexpected component kind {kind!r}")
            _merge(doc["components"].setdefault(kind, {}), components[kind],
                   f"{path.name} components.{kind}")
    return doc


def _merge(into: dict, items: dict, where: str) -> None:
    for key, value in items.items():
        if key in into:
            raise ValueError(f"{where}: {key!r} is already defined")
        into[key] = value


def render(doc: dict) -> str:
    """The bundle's canonical text: sorted keys, so regenerating is a no-op."""
    return json.dumps(doc, indent=2, sort_keys=True) + "\n"


def load() -> dict:
    """The committed bundle."""
    return json.loads(BUNDLE_PATH.read_text())


def main() -> None:
    BUNDLE_PATH.write_text(render(bundle()))
    print(f"wrote {BUNDLE_PATH}")


if __name__ == "__main__":
    main()
