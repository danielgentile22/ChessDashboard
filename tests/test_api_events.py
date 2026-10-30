"""
tests/test_api_events.py
========================
GET /api/v1/events: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getEvents.json for the iOS tests.
"""
from __future__ import annotations

from tests.test_api_event import ACC_MAY_2026


def test_events_matches_the_contract(api):
    body = api.get("/api/v1/events", record="getEvents")
    assert body["games_count"] > 0
    assert body["series"] and body["series_performance"]


def test_every_series_game_is_listed_once(api):
    body = api.get("/api/v1/events")
    listed = [row["game"]["game_id"] for s in body["series"]
              for group in [*s["rated_events"], {"games": s["unmatched_games"]}]
              for row in group["games"]]
    assert len(listed) == len(set(listed))
    assert len(listed) == sum(s["game_count"] + s["forfeit_count"] for s in body["series"])


def test_unplayed_events_follow_only_the_date_filter(api):
    everything = api.get("/api/v1/events")["unplayed_events"]
    assert everything
    # A color filter never turns a played event into an unplayed one
    assert api.get("/api/v1/events", query_string={"colors": "White"})["unplayed_events"] == everything
    dated = [e["start"] for e in everything if e["start"]]
    later = api.get("/api/v1/events", query_string={"start": max(dated)})["unplayed_events"]
    assert len(later) < len(everything)


def test_real_career_placements(api_real):
    body = api_real.get("/api/v1/events", record="getEvents.real_career")
    event = next(e for s in body["series"] for e in s["rated_events"]
                 if e["event_id"] == ACC_MAY_2026)
    placed = [s for s in event["sections"] if s["has_crosstable"]]
    assert placed and placed[0]["placement"] >= 1


def test_without_uscf_every_game_is_unmatched(api_lichess_only):
    body = api_lichess_only.get("/api/v1/events")
    assert body["unplayed_events"] == []
    assert all(s["rated_events"] == [] for s in body["series"])
    assert all(row["game"]["uscf_status"] == "unmatched"
               for s in body["series"] for row in s["unmatched_games"])
