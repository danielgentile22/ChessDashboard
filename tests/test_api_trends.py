"""
tests/test_api_trends.py
========================
GET /api/v1/trends: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getTrends.json for the iOS tests.

Pending until #112 builds the route: the strict xfail below fails the suite
the moment the route starts passing, so the ticket that builds it removes it.
"""
from __future__ import annotations

import pytest

PENDING = pytest.mark.xfail(strict=True, reason="#112: the route is a 501 stub")


@PENDING
def test_trends_matches_the_contract(api):
    body = api.get("/api/v1/trends", record="getTrends")
    assert body["games_count"] > 0
