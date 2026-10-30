"""
tests/test_ios_api_types.py
===========================
The iOS app's Swift request/response types are generated from
``openapi/v1.json`` and checked in.  This fails when the spec changed and the
Swift wasn't regenerated, so the contract and the phone can't drift.
Fix: ``.venv/bin/python ios/scripts/gen_api_types.py``.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest

_SPEC = importlib.util.spec_from_file_location(
    "gen_api_types",
    Path(__file__).resolve().parent.parent / "ios" / "scripts" / "gen_api_types.py",
)
gen = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(gen)


def test_generated_swift_matches_the_spec():
    assert gen.OUT.read_text() == gen.render(), (
        "APITypes.generated.swift is stale: run .venv/bin/python ios/scripts/gen_api_types.py")


def test_every_operation_has_a_factory_and_a_response_type():
    spec = json.loads(gen.SPEC.read_text())
    swift = gen.OUT.read_text()
    for methods in spec["paths"].values():
        for op in methods.values():
            op_id = op["operationId"]
            assert f"public static func {op_id}(" in swift
            assert f'"{op_id}": ' in swift


def _render(schemas: dict, paths: dict | None = None) -> str:
    spec = {"paths": paths or {}, "components": {"schemas": schemas, "parameters": {}}}
    return gen.Generator(spec).render(json.dumps(spec))


def test_nullable_and_optional_fields():
    swift = _render({"Thing": {
        "type": "object", "additionalProperties": False,
        "required": ["a", "b", "c"],
        "properties": {
            "a": {"type": ["integer", "null"]},
            "b": {"oneOf": [{"$ref": "#/components/schemas/Color"}, {"type": "null"}]},
            "c": {"type": "array", "items": {"type": "string"}},
            "snake_case": {"type": "boolean"},
        },
    }, "Color": {"type": "string", "enum": ["White", "Black"]}})
    assert "public var a: Int?" in swift
    assert "public var b: Color?" in swift
    assert "public var c: [String]\n" in swift
    assert "public var snakeCase: Bool?" in swift
    assert 'case snakeCase = "snake_case"' in swift
    assert 'case white = "White"' in swift


def test_unsupported_constructs_fail_loudly():
    with pytest.raises(ValueError):
        _render({"Open": {"type": "object", "properties": {}}})  # additionalProperties allowed
    with pytest.raises(ValueError):
        _render({"Either": {"type": "object", "additionalProperties": False, "properties": {
            "x": {"oneOf": [{"type": "string"}, {"type": "integer"}]}}}})


def test_colliding_enum_cases_fail():
    with pytest.raises(ValueError):
        _render({"E": {"type": "string", "enum": ["a-b", "a b"]}})


def test_check_mode_flags_staleness(tmp_path, monkeypatch):
    stale = tmp_path / "API.swift"
    stale.write_text("// old\n")
    monkeypatch.setattr(gen, "OUT", stale)
    assert gen.main(["--check"]) == 1
    assert gen.main([]) == 0
    assert gen.main(["--check"]) == 0
