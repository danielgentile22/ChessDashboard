"""
tests/test_api_opponent.py
==========================
GET /api/v1/opponents/{opponent_id}: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getOpponent.json for the iOS tests.
"""
from __future__ import annotations

from payloads.opponent_ids import name_id


def test_opponent_matches_the_contract(api):
    opponent_id = api.get("/api/v1/opponents")["opponents"][0]["opponent_id"]
    body = api.get(f"/api/v1/opponents/{opponent_id}", record="getOpponent")
    assert body["games_count"] > 0


def test_the_report_against_a_repeat_opponent(api):
    body = api.get("/api/v1/opponents/uscf-10000001")
    assert body["opponent"] == "Opponent A"
    assert body["record"] == {"games": 3, "win": 2, "draw": 1, "loss": 0,
                              "score_points": 2.5, "score": "2.5/3"}
    assert [g["opponent"] for g in body["games"]] == ["Opponent A"] * 3
    assert body["uscf_identity"]["member_id"] == "10000001"
    assert len(body["lessons"]) == 3
    assert {lesson["game"]["opponent"] for lesson in body["lessons"]} == {"Opponent A"}


def test_a_saved_name_id_still_resolves_and_answers_the_canonical_id(api):
    body = api.get(f"/api/v1/opponents/{name_id('Opponent A')}")
    assert body["opponent_id"] == "uscf-10000001"


def test_outside_the_filters_is_an_empty_report_not_a_404(api):
    body = api.get("/api/v1/opponents/uscf-10000001", query_string={"outcomes": "Loss"})
    assert body["games_count"] == 0
    assert body["record"]["games"] == 0 and body["record"]["score"] == "0/0"
    assert body["games"] == [] and body["uscf_identity"] is None


def test_an_unknown_opponent_is_a_404(api):
    body = api.get("/api/v1/opponents/uscf-99999999", status=404)
    assert body["error"]["code"] == "not_found"


def test_uscf_off_has_no_identity(api_lichess_only):
    opponent_id = name_id("Opponent A")
    body = api_lichess_only.get(f"/api/v1/opponents/{opponent_id}",
                                record="getOpponent.lichess_only")
    assert body["uscf_identity"] is None
    assert body["opponent_id"] == opponent_id


def test_then_vs_now_from_the_opponents_profile(ui_app, real_career_ui):
    import data
    from tests.api_contract import ApiHarness
    from tests.conftest import preserve_dash_callbacks

    with preserve_dash_callbacks():
        body = ApiHarness(ui_app.server.test_client()).get(
            "/api/v1/opponents/uscf-20000056", record="getOpponent.uscf_profile")
    identity = body["uscf_identity"]
    regular = data.get_opponent_profiles()["20000056"].rating("R")
    assert body["opponent"] == "Bob Baker"
    assert identity["profile_url"].endswith("/members/20000056")
    assert identity["current_rating"] == regular.rating
    assert identity["rating_change"] == regular.rating - identity["rating_when_last_played"]
