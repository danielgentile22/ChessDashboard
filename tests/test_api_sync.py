"""
tests/test_api_sync.py
======================
POST /api/v1/sync: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/runSync*.json for the iOS tests.

The route reports what the web Sync toast and celebration banner report, and
maps every other data.refresh() outcome onto the contract's status codes.
"""
from __future__ import annotations

from unittest import mock

import data
from api.routes import sync as sync_route
from lichess_client import LichessUnreachableError
from tests.conftest import stub_ui_sources


def test_sync_reports_new_games_and_milestones(api, sample_pgn_text,
                                               sample_pgn_study2_text):
    grown = sample_pgn_text + "\n\n" + sample_pgn_study2_text
    with stub_ui_sources(grown):
        body = api.post("/api/v1/sync", record="runSync")
    assert body["status"] == "success"
    assert {g["opponent"] for g in body["new_games"]} == {"Opponent E", "Opponent A"}
    new_ids = {g["game_id"] for g in body["new_games"]}
    assert new_ids <= {gid.rsplit("/", 1)[-1] for gid in data.get_df()["ChapterURL"]}
    assert {m["kind"] for m in body["milestones"]} >= {"peak_rating", "win_streak"}
    assert body["failures"] == []


def test_sync_with_nothing_new(api, sample_pgn_text):
    with stub_ui_sources(sample_pgn_text):
        body = api.post("/api/v1/sync", record="runSync.up_to_date")
    assert body["status"] == "success"
    assert body["new_games"] == [] and body["milestones"] == []


def test_sync_already_running(api):
    outcome = data.RefreshOutcome(status="already_running")
    with mock.patch.object(sync_route.data, "refresh", return_value=outcome):
        body = api.post("/api/v1/sync", record="runSync.already_running")
    assert body["status"] == "already_running"
    assert body["new_games"] == body["milestones"] == body["new_achievements"] == []


def test_failed_sync_is_502_and_keeps_the_data(api):
    before = data.get_df()
    with stub_ui_sources(""), mock.patch(
            "sync.fetch_study_pgn", side_effect=LichessUnreachableError("lichess is down")):
        body = api.post("/api/v1/sync", status=502)
    assert body["error"]["code"] == "sync_failed"
    assert data.get_df() is before


def test_demo_mode_is_forbidden(api):
    outcome = data.RefreshOutcome(status="demo",
                                  error="Demo mode is read-only; Sync is disabled.")
    with mock.patch.object(sync_route.data, "refresh", return_value=outcome):
        body = api.post("/api/v1/sync", status=403)
    assert body["error"] == {"code": "forbidden",
                             "message": "Demo mode is read-only; Sync is disabled."}


def test_guest_is_forbidden_before_any_sync(api):
    with mock.patch("auth.can_write", return_value=False), \
         mock.patch.object(sync_route.data, "refresh") as refresh:
        body = api.post("/api/v1/sync", status=403)
    assert body["error"]["code"] == "forbidden"
    refresh.assert_not_called()
