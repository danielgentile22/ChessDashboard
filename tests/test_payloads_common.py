"""
tests/test_payloads_common.py
=============================
The shapes every screen payload shares (``payloads.common``): the Game
summary row and the display rules it carries.
"""
from __future__ import annotations

import pytest

from payloads.common import game_summaries, tags, uscf_status, whole_rating
from tests.api_contract import validate

GAME_SUMMARY = {"type": "array", "items": {"$ref": "#/components/schemas/GameSummary"}}


class TestGameSummary:
    def test_every_game_row_matches_the_contract(self, ui_app, ui_data):
        import data

        rows = game_summaries(data.get_df())
        assert len(rows) == len(data.get_df())
        validate(rows, GAME_SUMMARY)

    def test_rows_with_uscf_off_still_carry_every_enrichment_field(self, api_lichess_only):
        import data

        rows = game_summaries(data.get_df())
        validate(rows, GAME_SUMMARY)
        assert {r["uscf_status"] for r in rows} == {"unmatched"}

    def test_the_live_lens_still_yields_whole_ratings(self, ui_app, ui_data):
        from filters import get_filtered

        df = get_filtered([], [], [], None, None, [], None, "live")
        rows = game_summaries(df)
        validate(rows, GAME_SUMMARY)
        assert all(isinstance(r["player_rating"], int) for r in rows if r["player_rating"])

    def test_the_game_id_is_the_web_deep_link_id(self, ui_app, ui_data):
        import data
        from components import game_detail_path

        df = data.get_df()
        row = game_summaries(df)[0]
        assert game_detail_path(df.iloc[0]["ChapterURL"]) == f"/game/{row['game_id']}"

    def test_an_empty_store_has_no_rows(self):
        import pandas as pd

        assert game_summaries(pd.DataFrame()) == []


class TestDisplayRules:
    @pytest.mark.parametrize("raw,expected", [
        (1570.72, 1571), ("1800", 1800), (0, None), ("", None), (None, None),
        (float("nan"), None), ("?", None), (True, None),
    ])
    def test_ratings_are_whole_numbers_or_null(self, raw, expected):
        assert whole_rating(raw) == expected

    def test_every_tag_carries_its_source(self):
        assert tags(["blunder", "tactics"], {"tactics": "engine"}) == [
            {"name": "blunder", "source": "mine"},
            {"name": "tactics", "source": "engine"},
        ]

    @pytest.mark.parametrize("matched_by,forfeit,conflict,expected", [
        ("id", False, False, "matched_by_id"),
        ("name", False, False, "matched_by_name"),
        ("id", False, True, "conflict"),
        ("", True, False, "forfeit"),
        ("", False, False, "unmatched"),
    ])
    def test_uscf_status_follows_the_web_table(self, matched_by, forfeit, conflict, expected):
        assert uscf_status(matched_by, forfeit, conflict) == expected
