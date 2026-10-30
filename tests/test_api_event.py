"""
tests/test_api_event.py
=======================
GET /api/v1/events/{event_id}: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getEvent.json for the iOS tests.

Pending until #113 builds the route: the strict xfail below fails the suite
the moment the route starts passing, so the ticket that builds it removes it.
"""
from __future__ import annotations

import pytest

import data

PENDING = pytest.mark.xfail(strict=True, reason="#113: the route is a 501 stub")


@PENDING
def test_event_matches_the_contract(api):
    event_id = next(e for e in data.get_df()["UscfEventId"] if e)
    body = api.get(f"/api/v1/events/{event_id}", record="getEvent")
    assert body["games_count"] > 0
