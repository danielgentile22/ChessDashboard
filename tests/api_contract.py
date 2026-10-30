"""
tests/api_contract.py
=====================
The API contract harness (ADR 0008): call a route through the Flask test
client, validate the response against ``openapi/v1.json``, and record the
validated body as a fixture the iOS tests decode.

Use it through the ``api`` fixture (``conftest.py``), which boots the real app
with the UI smoke harness's fixture data::

    def test_overview_matches_the_contract(api):
        body = api.get("/api/v1/overview", record="getOverview")
        assert body["games_count"] > 0

``record`` names the fixture file: ``openapi/fixtures/<record>.json``.  Use the
operationId, plus a ``.variant`` suffix for extra cases
(``getOverview.live_lens``).  By default the body is compared with the
committed fixture and a difference fails the test, so a payload change can't
drift away from what the iOS tests decode.  ``RECORD_FIXTURES=1`` rewrites the
fixtures instead.  Recording is deterministic: keys are sorted, volatile
values (tokens, ``*_at`` timestamps, the USCF-unavailable time) are pinned,
and a file is rewritten only when its content changes.
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker

from api.contract import ROOT, load

FIXTURE_DIR = ROOT / "fixtures"
SPEC = load()

PINNED_TIMESTAMP = "2026-01-01T00:00:00Z"
PINNED_TOKEN = "fixture-token"
_UNAVAILABLE_SINCE = re.compile(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2} UTC")


def _templates() -> list[tuple[re.Pattern, str]]:
    """Spec paths as regexes, static paths first so /games beats /games/{id}."""
    out = []
    for template in SPEC["paths"]:
        pattern = "^" + re.sub(r"\\\{[^}]+\\\}", "[^/]+", re.escape(template)) + "$"
        out.append((re.compile(pattern), template))
    return sorted(out, key=lambda pt: pt[1].count("{"))


_TEMPLATES = _templates()


def template_for(path: str) -> str:
    """The spec path template a concrete request path matches."""
    for pattern, template in _TEMPLATES:
        if pattern.match(path):
            return template
    raise AssertionError(f"{path} matches no path in openapi/v1.json")


def _resolve(node: dict) -> dict:
    while "$ref" in node:
        kind, name = node["$ref"].split("/")[-2:]
        node = SPEC["components"][kind][name]
    return node


def response_schema(method: str, template: str, status: int) -> dict:
    """The JSON schema the spec declares for one operation's status code."""
    operation = SPEC["paths"][template].get(method.lower())
    assert operation is not None, f"{method.upper()} {template} is not in the spec"
    declared = operation["responses"].get(str(status))
    assert declared is not None, (
        f"{method.upper()} {template} returned {status}, which the spec doesn't declare")
    return _resolve(declared)["content"]["application/json"]["schema"]


def validate(body: Any, schema: dict) -> None:
    """Validate *body* against *schema*, resolving refs inside the spec."""
    root = {**schema, "components": SPEC["components"]}
    validator = Draft202012Validator(root, format_checker=FormatChecker())
    errors = sorted(validator.iter_errors(body), key=lambda e: list(e.absolute_path))
    if errors:
        detail = "\n".join(
            f"  at {'/'.join(map(str, e.absolute_path)) or '<root>'}: {e.message}"
            for e in errors[:10])
        raise AssertionError(f"response violates the contract:\n{detail}")


def pin_volatile(value: Any, key: str = "") -> Any:
    """*value* with per-run values pinned, so re-recording never churns."""
    if isinstance(value, dict):
        return {k: pin_volatile(v, k) for k, v in value.items()}
    if isinstance(value, list):
        return [pin_volatile(v) for v in value]
    if value is None:
        return None
    if key == "token":
        return PINNED_TOKEN
    if key.endswith("_at") and isinstance(value, str):
        return PINNED_TIMESTAMP
    if key == "unavailable_since" and isinstance(value, str):
        return _UNAVAILABLE_SINCE.sub("2026-01-01 00:00 UTC", value)
    return value


def recording() -> bool:
    """Whether this run may rewrite fixtures (``RECORD_FIXTURES=1``)."""
    return os.environ.get("RECORD_FIXTURES") == "1"


def record(name: str, body: Any) -> Path:
    """Check *body* against ``openapi/fixtures/<name>.json``, failing on any
    drift; with ``RECORD_FIXTURES=1``, write it instead (only if it changed)."""
    path = FIXTURE_DIR / f"{name}.json"
    text = json.dumps(pin_volatile(body), indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    if path.exists() and path.read_text() == text:
        return path
    if not recording():
        raise AssertionError(
            f"openapi/fixtures/{name}.json is {'stale' if path.exists() else 'missing'}: "
            "rerun the tests with RECORD_FIXTURES=1 and commit the fixture")
    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path


class ApiHarness:
    """A test client whose every call is checked against the contract."""

    def __init__(self, client) -> None:
        self.client = client

    def request(self, method: str, path: str, *, status: int = 200,
                record_as: str | None = None, **kwargs) -> Any:
        """Call *path*, assert *status*, validate the body against the spec's
        schema for that status, optionally record it, and return the body."""
        resp = self.client.open(path, method=method.upper(), **kwargs)
        body = resp.get_json(silent=True)
        assert resp.status_code == status, (
            f"{method.upper()} {path}: expected {status}, got {resp.status_code}: {body}")
        assert body is not None, f"{method.upper()} {path}: not a JSON response"
        validate(body, response_schema(method, template_for(resp.request.path), status))
        if record_as:
            record(record_as, body)
        return body

    def get(self, path: str, *, record: str | None = None, **kwargs) -> Any:
        return self.request("get", path, record_as=record, **kwargs)

    def post(self, path: str, *, record: str | None = None, **kwargs) -> Any:
        return self.request("post", path, record_as=record, **kwargs)
