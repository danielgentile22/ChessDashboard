"""
tests/test_api_trends.py
========================
GET /api/v1/trends: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getTrends.json for the iOS tests.
"""
from __future__ import annotations


def test_trends_matches_the_contract(api):
    body = api.get("/api/v1/trends", record="getTrends")
    assert body["games_count"] > 0
    assert body["calendar"]
    chart = body["rating_chart"]
    assert chart["mode"] == "uscf"
    assert chart["emphasized"] == "official"
    assert chart["official"] or chart["live"]
    assert chart["typed"] == []


def test_trends_lens_only_changes_the_emphasis(api):
    official = api.get("/api/v1/trends")["rating_chart"]
    live = api.get("/api/v1/trends", query_string={"lens": "live"})["rating_chart"]
    assert live["emphasized"] == "live"
    assert (live["official"], live["live"]) == (official["official"], official["live"])


def test_trends_with_no_matching_games_is_the_empty_state(api):
    body = api.get("/api/v1/trends", query_string={"start": "2099-01-01"},
                   record="getTrends.empty")
    assert body["games_count"] == 0
    assert body["calendar"] == []
    assert body["rating_chart"]["official"] == body["rating_chart"]["live"] == []
    assert body["average_length"] == {"win": None, "draw": None, "loss": None}


def test_trends_without_uscf_degrades_to_typed_ratings(api_lichess_only):
    body = api_lichess_only.get("/api/v1/trends", record="getTrends.lichess_only")
    chart = body["rating_chart"]
    assert chart["mode"] == "typed"
    assert chart["official"] == chart["live"] == []
    assert chart["typed"]


def test_trends_upsets_carry_the_game(api):
    upsets = api.get("/api/v1/trends")["upsets"]
    for row in upsets["giant_kills"]:
        assert row["game"]["outcome"] == "Win"
        assert row["margin"] > 0
    for row in upsets["upset_losses"]:
        assert row["game"]["outcome"] == "Loss"
