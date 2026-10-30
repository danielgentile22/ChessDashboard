"""
tests/test_api_analysis.py
==========================
GET /api/v1/analysis: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getAnalysis.json for the iOS tests.

Pending until #115 builds the route: the strict xfail below fails the suite
the moment the route starts passing, so the ticket that builds it removes it.
"""
from __future__ import annotations

import pytest

PENDING = pytest.mark.xfail(strict=True, reason="#115: the route is a 501 stub")


@PENDING
def test_analysis_matches_the_contract(api):
    body = api.get("/api/v1/analysis", record="getAnalysis")
    assert body
