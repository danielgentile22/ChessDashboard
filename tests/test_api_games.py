"""
tests/test_api_games.py
=======================
GET /api/v1/games: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getGames.json for the iOS tests.

Pending until #113 builds the route: the strict xfail below fails the suite
the moment the route starts passing, so the ticket that builds it removes it.
"""
from __future__ import annotations

import pytest

PENDING = pytest.mark.xfail(strict=True, reason="#113: the route is a 501 stub")


@PENDING
def test_games_matches_the_contract(api):
    body = api.get("/api/v1/games", record="getGames")
    assert body["games_count"] == len(body["games"]) > 0
