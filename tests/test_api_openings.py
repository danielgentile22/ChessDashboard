"""
tests/test_api_openings.py
==========================
GET /api/v1/openings: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getOpenings.json for the iOS tests.
"""
from __future__ import annotations


def _nodes(nodes):
    for node in nodes:
        yield node
        yield from _nodes(node["moves"])


def test_openings_matches_the_contract(api):
    body = api.get("/api/v1/openings", record="getOpenings")
    assert body["games_count"] > 0


def test_branches_drill_into_real_games(api):
    body = api.get("/api/v1/openings")
    game_ids = {g["game_id"] for g in api.get("/api/v1/games")["games"]}
    for tree in body["repertoire"].values():
        for node in _nodes(tree["moves"]):
            assert len(node["games"]) == node["game_count"]
            assert {g["game_id"] for g in node["ended_here"]} <= {g["game_id"] for g in node["games"]}
            assert {g["game_id"] for g in node["games"]} <= game_ids
            if node["game_count"] == 1:
                assert node["moves"] == []


def test_both_colors_are_embedded_whatever_the_color_filter(api):
    body = api.get("/api/v1/openings", query_string={"colors": "White"})
    assert body["repertoire"]["white"]["game_count"] > 0
    assert body["repertoire"]["black"]["game_count"] == 0  # the empty state
    assert body["repertoire"]["black"]["moves"] == []


def test_no_matching_games_is_every_empty_state(api):
    body = api.get("/api/v1/openings", query_string={"start": "2099-01-01"})
    assert body["games_count"] == 0
    assert body["eco_families"] == [] and body["top_openings"] == []
