"""
tests/test_api_sync.py
======================
POST /api/v1/sync: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/runSync.json for the iOS tests.

Pending until #115 builds the route: the strict xfail below fails the suite
the moment the route starts passing, so the ticket that builds it removes it.
"""
from __future__ import annotations

import pytest

PENDING = pytest.mark.xfail(strict=True, reason="#115: the route is a 501 stub")


@PENDING
def test_sync_matches_the_contract(api):
    body = api.post("/api/v1/sync", record="runSync")
    assert body
