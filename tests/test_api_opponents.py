"""
tests/test_api_opponents.py
===========================
GET /api/v1/opponents: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getOpponents.json for the iOS tests.
"""
from __future__ import annotations


def test_opponents_matches_the_contract(api):
    body = api.get("/api/v1/opponents", record="getOpponents")
    assert body["games_count"] > 0


def test_the_picker_is_unfiltered_and_carries_canonical_ids(api):
    body = api.get("/api/v1/opponents", query_string={"colors": "Black"})
    assert [o["opponent"] for o in body["opponents"]] == [
        "Opponent A", "Opponent B", "Opponent C", "Opponent D"]
    assert body["opponents"][0]["opponent_id"] == "uscf-10000001"


def test_records_list_repeat_opponents_most_games_first(api):
    records = api.get("/api/v1/opponents")["records"]
    assert [(r["opponent"], r["games"], r["win"], r["draw"], r["loss"]) for r in records] == [
        ("Opponent A", 3, 2, 1, 0), ("Opponent B", 2, 1, 1, 0)]
    assert records[0]["opponent_id"] == "uscf-10000001"


def test_the_scatter_and_buckets_honor_the_filters(api):
    body = api.get("/api/v1/opponents", query_string={"outcomes": "Loss"})
    assert body["games_count"] == 1
    assert {p["outcome"] for p in body["outcome_vs_rating"]} <= {"Loss"}
    assert sum(b["games"] for b in body["rating_buckets"]) <= 1


def test_uscf_off_still_validates(api_lichess_only):
    body = api_lichess_only.get("/api/v1/opponents", record="getOpponents.lichess_only")
    assert all(o["opponent_id"].startswith("name-") for o in body["opponents"])
