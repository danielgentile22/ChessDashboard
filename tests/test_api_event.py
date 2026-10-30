"""
tests/test_api_event.py
=======================
GET /api/v1/events/{event_id}: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getEvent.json (sample data) and
getEvent.real_career.json (cached crosstables, round links) for the iOS tests.
"""
from __future__ import annotations

import data

# ACC MAY 2026: its Section 1 crosstable is cached in the real-career fixtures.
ACC_MAY_2026 = "202605290393"


def test_event_matches_the_contract(api):
    event_id = next(e for e in data.get_df()["UscfEventId"] if e)
    body = api.get(f"/api/v1/events/{event_id}", record="getEvent")
    assert body["games_count"] > 0
    assert body["event_id"] == event_id
    assert body["series"]


def test_crosstables_link_the_players_rounds_to_his_games(api_real):
    body = api_real.get(f"/api/v1/events/{ACC_MAY_2026}", record="getEvent.real_career")
    with_table = [s for s in body["sections"] if s["has_crosstable"]]
    assert with_table
    section = with_table[0]
    assert section["player_count"] == len(section["crosstable"])

    mine = [row for row in section["crosstable"] if row["is_player"]]
    assert len(mine) == 1
    assert mine[0]["ordinal"] == section["placement"]
    linked = {r["game_id"] for r in mine[0]["rounds"] if r["game_id"]}
    assert linked
    assert linked <= {row["game"]["game_id"] for row in body["games"]}
    # Only the player's own row links to Games
    others = [r for row in section["crosstable"] if not row["is_player"] for r in row["rounds"]]
    assert all(r["game_id"] is None for r in others)


def test_unknown_event_is_a_json_404(api):
    body = api.get("/api/v1/events/000000000000", status=404)
    assert body["error"]["code"] == "not_found"


def test_entered_but_never_played_event_is_404(api):
    unplayed = api.get("/api/v1/events")["unplayed_events"]
    assert unplayed
    api.get(f"/api/v1/events/{unplayed[0]['event_id']}", status=404)


def test_filters_hiding_every_game_still_answer_200(api):
    event_id = next(e for e in data.get_df()["UscfEventId"] if e)
    body = api.get(f"/api/v1/events/{event_id}", query_string={"start": "2099-01-01"})
    assert body["games_count"] == 0
    assert body["games"] == [] and body["sections"] == [] and body["series"] == []
    assert body["name"]  # the Rated Event still has its official name
    assert body["rating_change"] is None


def test_without_uscf_no_event_exists(api_lichess_only):
    api_lichess_only.get("/api/v1/events/202401070001", status=404)
