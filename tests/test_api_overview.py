"""
tests/test_api_overview.py
==========================
GET /api/v1/overview: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getOverview.json for the iOS tests.
"""
from __future__ import annotations


def test_overview_matches_the_contract(api):
    body = api.get("/api/v1/overview", record="getOverview")
    assert body["games_count"] > 0
    assert body["uscf_card"]["state"] == "ok"
    assert body["milestones"]
    assert body["streak"]["last_20"]


def test_overview_follows_the_filters(api):
    body = api.get("/api/v1/overview", query_string={"outcomes": "Win"})
    assert body["kpis"]["win_pct"] == 100.0
    assert body["outcome_counts"]["loss"] == 0
    assert body["games_count"] < api.get("/api/v1/overview")["games_count"]


def test_overview_uscf_card_ignores_filters_and_lens(api):
    everything = api.get("/api/v1/overview")["uscf_card"]
    narrowed = api.get("/api/v1/overview",
                       query_string={"colors": "White", "lens": "live"})["uscf_card"]
    assert narrowed == everything


def test_overview_with_no_matching_games_is_the_empty_state(api):
    body = api.get("/api/v1/overview", query_string={"start": "2099-01-01"},
                   record="getOverview.empty")
    assert body["games_count"] == 0
    assert body["streak"]["current_outcome"] is None
    assert body["kpis"]["favorite_opening"] == ""
    assert body["terminations"] == []


def test_overview_without_uscf_has_no_card(api_lichess_only):
    body = api_lichess_only.get("/api/v1/overview", record="getOverview.lichess_only")
    assert body["uscf_card"] == {"state": "disabled", "profile": None,
                                 "unavailable_reason": "", "unavailable_since": None}
    assert all(m["kind"] != "uscf" for m in body["milestones"])


def test_overview_rejects_a_bad_lens(api):
    body = api.get("/api/v1/overview", query_string={"lens": "nope"}, status=400)
    assert body["error"]["code"] == "bad_request"
