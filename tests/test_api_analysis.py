"""
tests/test_api_analysis.py
==========================
GET /api/v1/analysis: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getAnalysis*.json for the iOS tests.
"""
from __future__ import annotations

import pytest

import data
from pgn_stats_core import chapter_id
from tests.api_career import ANALYZED_ID, career_store
from tests.conftest import preserve_dash_callbacks


@pytest.fixture()
def career(ui_app, tmp_path):
    from tests.api_contract import ApiHarness

    with career_store(tmp_path), preserve_dash_callbacks():
        yield ApiHarness(ui_app.server.test_client())


def test_analysis_matches_the_contract(career):
    body = career.get("/api/v1/analysis", record="getAnalysis")
    assert body["has_analysis"] is True
    assert [p["game_id"] for p in body["accuracy_trend"]] == [ANALYZED_ID]
    assert [p["game_id"] for p in body["mistake_type_trend"]] == [ANALYZED_ID]
    dist = body["mistake_type_distribution"]
    assert dist["tactical"] + dist["positional"] == sum(
        b["count"] for b in body["mistake_move_histogram"])
    assert [r["phase"] for r in body["phase_type_matrix"]] == [
        "opening", "middlegame", "endgame"]
    awaiting = {a["game_id"] for a in body["awaiting_analysis"]}
    assert ANALYZED_ID not in awaiting
    assert len(awaiting) == len(data.get_awaiting_analysis())


def test_no_analysis_yet_is_the_empty_state(api):
    body = api.get("/api/v1/analysis", record="getAnalysis.empty")
    assert body["has_analysis"] is False
    assert body["mistake_type_distribution"] == {"tactical": 0, "positional": 0}
    assert body["accuracy_trend"] == body["mistake_type_trend"] == []
    assert body["phase_type_matrix"] == body["mistake_move_histogram"] == []
    assert {a["game_id"] for a in body["awaiting_analysis"]} == {
        chapter_id(u) for u in data.get_df()["ChapterURL"] if u}
