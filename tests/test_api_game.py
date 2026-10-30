"""
tests/test_api_game.py
======================
GET /api/v1/games/{game_id}: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getGame.json for the iOS tests.

Pending until #115 builds the route: the strict xfail below fails the suite
the moment the route starts passing, so the ticket that builds it removes it.
"""
from __future__ import annotations

import pytest

import data
from pgn_stats_core import chapter_id

PENDING = pytest.mark.xfail(strict=True, reason="#115: the route is a 501 stub")


@PENDING
def test_game_matches_the_contract(api):
    game_id = chapter_id(data.get_df().iloc[0]["ChapterURL"])
    body = api.get(f"/api/v1/games/{game_id}", record="getGame")
    assert body
