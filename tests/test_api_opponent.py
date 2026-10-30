"""
tests/test_api_opponent.py
==========================
GET /api/v1/opponents/{opponent_id}: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getOpponent.json for the iOS tests.

Pending until #114 builds the route: the strict xfail below fails the suite
the moment the route starts passing, so the ticket that builds it removes it.
"""
from __future__ import annotations

import pytest

PENDING = pytest.mark.xfail(strict=True, reason="#114: the route is a 501 stub")


@PENDING
def test_opponent_matches_the_contract(api):
    opponent_id = api.get("/api/v1/opponents")["opponents"][0]["opponent_id"]
    body = api.get(f"/api/v1/opponents/{opponent_id}", record="getOpponent")
    assert body["games_count"] > 0
