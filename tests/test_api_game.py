"""
tests/test_api_game.py
======================
GET /api/v1/games/{game_id}: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getGame*.json for the iOS tests.

The board PGNs are the ones the web Game detail page feeds pgn-viewer, so the
native board (#120) parses exactly what the web plays.  One fixture per board
view: My Analysis, an engine-analyzed Game, a Coach view, an un-analyzed Game.
"""
from __future__ import annotations

import pytest

import data
from pgn_stats_core import chapter_id
from tests.api_career import (
    ANALYZED_ID,
    COACH_ID,
    MY_ANALYSIS_ID,
    UNANALYZED_ID,
    career_store,
)
from tests.conftest import preserve_dash_callbacks


def _game_with_lesson():
    df = data.get_df()
    return df[df["Lessons"].map(bool) & df["UscfMatched"]].iloc[0]


def test_game_matches_the_contract(api):
    game = _game_with_lesson()
    body = api.get(f"/api/v1/games/{chapter_id(game['ChapterURL'])}", record="getGame")
    assert body["game"]["chapter_url"] == game["ChapterURL"]
    assert body["lessons"] == list(game["Lessons"])
    assert body["uscf_record"] is not None
    assert body["board"]["game"].startswith("[Event ")


def test_unknown_game_is_404(api):
    body = api.get("/api/v1/games/nosuchgame", status=404)
    assert body["error"]["code"] == "not_found"


def test_lichess_only_game_has_no_uscf_record(api_lichess_only):
    game_id = chapter_id(data.get_df().iloc[0]["ChapterURL"])
    body = api_lichess_only.get(f"/api/v1/games/{game_id}")
    assert body["uscf_record"] is None


@pytest.fixture()
def career(ui_app, tmp_path):
    from tests.api_contract import ApiHarness

    with career_store(tmp_path), preserve_dash_callbacks():
        yield ApiHarness(ui_app.server.test_client())


def _board_attrs(game_id: str) -> dict:
    """The data-pgn-* attributes the web page puts on the pgn-viewer mount."""
    from pages import game_detail  # registers a Dash page: needs ui_app first

    found: dict = {}

    def walk(node):
        if isinstance(node, (list, tuple)):
            for child in node:
                walk(child)
            return
        if node is None or isinstance(node, str):
            return
        for key in ("data-pgn-game", "data-pgn-analysis", "data-pgn-coach"):
            value = getattr(node, key, None)
            if value:
                found[key] = value
        walk(getattr(node, "children", None))

    walk(game_detail.layout(chapter_id=game_id))
    return found


def _assert_same_pgns_as_the_web(body: dict, game_id: str) -> None:
    attrs = _board_attrs(game_id)
    assert body["board"]["game"] == attrs.get("data-pgn-game")
    assert body["board"]["my_analysis"] == attrs.get("data-pgn-analysis")
    assert body["board"]["coach"] == attrs.get("data-pgn-coach")


def test_engine_analyzed_game(career):
    body = career.get(f"/api/v1/games/{ANALYZED_ID}", record="getGame.analyzed")
    engine = body["engine"]
    assert engine["state"] == "analyzed"
    assert engine["win_probability"] and engine["judged_moves"]
    assert engine["critical_moment"] is not None
    assert body["board"]["engine"] is not None and "[%eval" in body["board"]["engine"]
    assert {"name": "strategy", "source": "engine"} in body["tags"]
    _assert_same_pgns_as_the_web(body, ANALYZED_ID)


def test_my_analysis_game(career):
    body = career.get(f"/api/v1/games/{MY_ANALYSIS_ID}", record="getGame.my_analysis")
    assert body["board"]["my_analysis"] is not None
    assert body["board"]["coach"] is None
    _assert_same_pgns_as_the_web(body, MY_ANALYSIS_ID)


def test_coach_view_game(career):
    body = career.get(f"/api/v1/games/{COACH_ID}", record="getGame.coach")
    assert body["board"]["coach"] is not None
    _assert_same_pgns_as_the_web(body, COACH_ID)


def test_unanalyzed_game_awaits_analysis(career):
    body = career.get(f"/api/v1/games/{UNANALYZED_ID}", record="getGame.unanalyzed")
    assert body["engine"] == {"state": "awaiting_analysis", "ai_summary": "",
                              "win_probability": [], "judged_moves": [],
                              "critical_moment": None}
    assert body["board"]["engine"] is None
    assert body["board"]["coach"] is None
    _assert_same_pgns_as_the_web(body, UNANALYZED_ID)


def test_forfeit_is_flagged(career):
    df = data.get_df()
    forfeit = df[df["Forfeit"].astype(bool)].iloc[0]
    body = career.get(f"/api/v1/games/{chapter_id(forfeit['ChapterURL'])}")
    assert body["forfeit"] is True
