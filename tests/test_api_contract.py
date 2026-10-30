"""
tests/test_api_contract.py
==========================
The API contract itself (ADR 0008), plus the routes this foundation serves
(session, meta).

* ``openapi/v1.json`` is the up-to-date bundle of ``openapi/src/``.
* Every response object is closed and fully required, so enrichment can't
  silently go missing and a new field can't ship undocumented.
* Every operation in the document has a Flask route, and every route is in
  the document.
* Screen routes still on their 501 stub answer with the contract's error
  body.

Each screen's own contract test lives in ``test_api_<screen>.py``.
"""
from __future__ import annotations

import re

import pytest

from api import contract
from tests.api_contract import PINNED_TOKEN, SPEC, pin_volatile, record, response_schema, validate
from tests.conftest import API_TODAY

API_ROOT = "/api/v1"
_METHODS = {"get", "post", "put", "patch", "delete"}


def _operations():
    for template, item in SPEC["paths"].items():
        for method, op in item.items():
            if method in _METHODS:
                yield method, template, op


def _request_schema_names() -> set[str]:
    names = set()
    for _m, _t, op in _operations():
        body = op.get("requestBody", {}).get("content", {}).get("application/json", {})
        ref = body.get("schema", {}).get("$ref", "")
        if ref:
            names.add(ref.rsplit("/", 1)[-1])
    return names


def _object_schemas(node, where):
    """Every inline or named object schema under *node*, with a locator."""
    if isinstance(node, dict):
        if node.get("type") == "object" or (
                isinstance(node.get("type"), list) and "object" in node["type"]):
            yield where, node
        for key, value in node.items():
            yield from _object_schemas(value, f"{where}/{key}")
    elif isinstance(node, list):
        for i, value in enumerate(node):
            yield from _object_schemas(value, f"{where}/{i}")


class TestDocument:
    def test_the_bundle_is_up_to_date(self):
        assert contract.render(contract.bundle()) == contract.BUNDLE_PATH.read_text(), (
            "openapi/v1.json is stale: run `python -m api.contract`")

    def test_it_is_openapi_3_1(self):
        assert SPEC["openapi"].startswith("3.1")

    def test_every_ref_resolves(self):
        refs = re.findall(r'"\$ref": "#/components/(\w+)/(\w+)"', contract.render(SPEC))
        missing = {f"{k}/{n}" for k, n in refs if n not in SPEC["components"].get(k, {})}
        assert not missing

    def test_every_response_object_is_closed_and_fully_required(self):
        """Enrichment fields are always present (ADR 0003/0004), and a field
        the document doesn't name can't ship."""
        requests = _request_schema_names()
        bad = []
        for name, schema in SPEC["components"]["schemas"].items():
            if name in requests:
                continue
            for where, obj in _object_schemas(schema, name):
                props = set(obj.get("properties", {}))
                if obj.get("additionalProperties") is not False:
                    bad.append(f"{where}: additionalProperties must be false")
                if props != set(obj.get("required", [])):
                    bad.append(f"{where}: required must list every property")
        assert not bad, "\n".join(bad)

    def test_operation_ids_are_unique(self):
        ids = [op["operationId"] for _m, _t, op in _operations()]
        assert len(ids) == len(set(ids))

    def test_every_route_in_the_spec_covers_the_issue(self):
        expected = {
            ("post", "/session"), ("get", "/meta"), ("get", "/overview"),
            ("get", "/trends"), ("get", "/openings"), ("get", "/opponents"),
            ("get", "/opponents/{opponent_id}"), ("get", "/events"),
            ("get", "/events/{event_id}"), ("get", "/games"), ("get", "/lessons"),
            ("get", "/analysis"), ("get", "/games/{game_id}"), ("post", "/sync"),
        }
        actual = {(m, t.removeprefix(API_ROOT)) for m, t, _op in _operations()}
        assert actual == expected


class TestRoutesMatchTheDocument:
    def _flask_routes(self, ui_app):
        routes = set()
        for rule in ui_app.server.url_map.iter_rules():
            if not rule.rule.startswith(API_ROOT) or "<path:" in rule.rule:
                continue
            template = re.sub(r"<(?:\w+:)?(\w+)>", r"{\1}", rule.rule)
            routes |= {(m.lower(), template) for m in rule.methods - {"HEAD", "OPTIONS"}}
        return routes

    def test_every_operation_has_a_route_and_back(self, ui_app):
        documented = {(m, t) for m, t, _op in _operations()}
        assert self._flask_routes(ui_app) == documented

    def test_an_unknown_api_path_body_is_the_error_shape(self, api):
        resp = api.client.get("/api/v1/nope")
        assert resp.status_code == 404
        validate(resp.get_json(), {"$ref": "#/components/schemas/Error"})
        assert resp.get_json()["error"]["code"] == "not_found"


def _stub_paths():
    """A concrete request path per documented operation (ids are dummies)."""
    for method, template, op in _operations():
        path = re.sub(r"\{\w+\}", "unknown-id", template)
        yield pytest.param(method, path, id=op["operationId"])


@pytest.mark.parametrize("method,path", list(_stub_paths()))
def test_every_route_answers_json_matching_the_error_shape_or_its_schema(
        api, method, path):
    """A stubbed screen answers 501 with the error body; a built one answers
    something the document declares.  Either way: JSON, never Dash's HTML."""
    resp = api.client.open(path, method=method.upper(), json={})
    body = resp.get_json(silent=True)
    assert body is not None, f"{method} {path} returned non-JSON"
    if resp.status_code == 501:
        validate(body, {"$ref": "#/components/schemas/Error"})
        assert body["error"]["code"] == "not_implemented"


class TestSession:
    def test_ungated_sign_in_matches_the_contract(self, api):
        body = api.post("/api/v1/session", json={}, record="createSession")
        assert body["role"] == "owner"

    def test_bad_credentials_body_matches_the_contract(self, api):
        api.post("/api/v1/session", data="x", content_type="text/plain", status=400)


class TestMeta:
    def test_meta_matches_the_contract(self, api):
        body = api.get("/api/v1/meta", record="getMeta")
        assert body["player"] == "Test Player"
        assert body["games_total"] > 0
        assert body["session"] == {"role": "owner", "username": None, "can_write": True}
        assert body["freshness"]["uscf"]["enabled"] is True

    def test_filter_options_follow_the_web_drawer(self, api, ui_data):
        import data
        from filters import _data_bounds

        b = _data_bounds(data.get_df())
        options = api.get("/api/v1/meta")["filter_options"]
        assert options == {
            "terminations": b["terminations"], "series": b["events"],
            "min_date": b["min_date"], "max_date": b["max_date"],
            "min_moves": b["min_mv"], "max_moves": b["max_mv"],
        }

    def test_presets_match_the_web_presets(self, api):
        presets = {p["id"]: p["filters"] for p in api.get("/api/v1/meta")["presets"]}
        assert list(presets) == ["all", "last_20", "this_year", "white", "black", "wins"]
        assert presets["this_year"]["start"] == f"{API_TODAY.year}-01-01"
        assert presets["white"]["colors"] == ["White"]
        assert presets["wins"]["outcomes"] == ["Win"]
        assert presets["last_20"]["start"] is not None

    def test_meta_with_uscf_off_still_matches(self, api_lichess_only):
        body = api_lichess_only.get("/api/v1/meta", record="getMeta.lichess_only")
        assert body["freshness"]["uscf"] == {
            "enabled": False, "available": False, "synced_at": None,
            "unavailable_since": None}


class TestFilterParsing:
    @pytest.mark.parametrize("query", [
        "colors=Purple", "outcomes=Maybe", "lens=vibes", "start=yesterday",
        "min_moves=ten",
    ])
    def test_a_malformed_filter_is_a_400(self, query):
        from flask import Flask

        from api.http import ApiError, parse_filters

        with Flask(__name__).test_request_context(f"/?{query}") as ctx:
            with pytest.raises(ApiError) as exc:
                parse_filters(ctx.request.args)
        assert exc.value.status == 400 and exc.value.code == "bad_request"

    def test_filters_parse_one_to_one_with_filter_inputs(self):
        from flask import Flask

        from api.http import parse_filters

        q = ("colors=White&outcomes=Win&outcomes=Draw&terminations=Normal&start=2024-01-01"
             "&end=2024-12-31&series=Ladder&series=Open&min_moves=10&max_moves=60&lens=live")
        with Flask(__name__).test_request_context(f"/?{q}") as ctx:
            f = parse_filters(ctx.request.args)
        assert (f.colors, f.outcomes, f.terminations, f.start, f.end, f.series,
                f.min_moves, f.max_moves, f.lens) == (
            ["White"], ["Win", "Draw"], ["Normal"], "2024-01-01", "2024-12-31",
            ["Ladder", "Open"], 10, 60, "live")

    def test_omitted_filters_mean_no_restriction_and_the_official_lens(self, ui_app, ui_data):
        from flask import Flask

        import data
        from api.http import filtered_games, parse_filters

        with Flask(__name__).test_request_context("/"):
            from flask import request
            games = filtered_games(parse_filters(request.args))
        assert len(games) == len(data.get_df())


class TestRecording:
    def test_volatile_values_are_pinned(self):
        pinned = pin_volatile({"token": "abc", "synced_at": "2026-10-29T10:00:00Z",
                               "nested": [{"cached_at": None}],
                               "unavailable_since": "USCF unavailable since 2026-10-29 10:00 UTC"})
        assert pinned == {"token": PINNED_TOKEN, "synced_at": "2026-01-01T00:00:00Z",
                          "nested": [{"cached_at": None}],
                          "unavailable_since": "USCF unavailable since 2026-01-01 00:00 UTC"}

    def test_recording_twice_leaves_the_file_untouched(self, tmp_path, monkeypatch):
        import tests.api_contract as harness

        monkeypatch.setattr(harness, "FIXTURE_DIR", tmp_path)
        path = record("x", {"b": 1, "a": [2]})
        mtime = path.stat().st_mtime_ns
        record("x", {"a": [2], "b": 1})
        assert path.stat().st_mtime_ns == mtime
        assert path.read_text() == '{\n  "a": [\n    2\n  ],\n  "b": 1\n}\n'

    def test_an_undeclared_status_fails_loudly(self):
        with pytest.raises(AssertionError, match="doesn't declare"):
            response_schema("get", "/api/v1/meta", 418)

