"""
tests/test_api_games.py
=======================
GET /api/v1/games: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getGames.json for the iOS tests.
"""
from __future__ import annotations


def test_games_matches_the_contract(api):
    body = api.get("/api/v1/games", record="getGames")
    assert body["games_count"] == len(body["games"]) > 0


def test_filters_select_the_same_games_as_the_web_table(api):
    from pages.games import update_games_table  # pages register once the app exists

    body = api.get("/api/v1/games", query_string={"colors": "White"})
    web = update_games_table(["White"], [], [], None, None, [], None)
    assert [g["chapter_url"] for g in body["games"]] == [r["ChapterURL"] for r in web]
    assert {g["color"] for g in body["games"]} == {"White"}


def test_the_lens_never_hides_games(api):
    official = api.get("/api/v1/games", query_string={"lens": "official"})
    live = api.get("/api/v1/games", query_string={"lens": "live"})
    assert official["games_count"] == live["games_count"]


def test_without_uscf_every_game_is_unmatched(api_lichess_only):
    body = api_lichess_only.get("/api/v1/games")
    assert body["games"]
    assert {g["uscf_status"] for g in body["games"]} == {"unmatched"}
