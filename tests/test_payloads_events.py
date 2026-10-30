"""
tests/test_payloads_events.py
=============================
The Rated Event assembly that moved out of pages/events.py into
payloads.events, so the web card and the API can't drift.
"""
from __future__ import annotations

import math

import pytest

from payloads.events import player_entry, rating_change, round_chapter_urls
from uscf_core import StandingEntry


def _entry(ordinal: int, member_id: str) -> StandingEntry:
    return StandingEntry(ordinal=ordinal, member_id=member_id, name=member_id,
                         score=0.0, pre_rating=None, post_rating=None, rounds=())


class TestRatingChange:
    @pytest.mark.parametrize("pre, post, expected", [
        (1544.4, 1570.6, 27),   # whole numbers first, then the difference
        (1600.0, 1588.0, -12),
        (None, 695.0, None),    # walked in unrated
        (1500.0, None, None),
    ])
    def test_whole_number_difference(self, pre, post, expected):
        assert rating_change(pre, post) == expected


class TestPlayerEntry:
    def test_finds_the_players_row(self):
        table = [_entry(1, "111"), _entry(2, "222")]
        assert player_entry(table, "222").ordinal == 2

    def test_no_member_id_matches_nobody(self):
        assert player_entry([_entry(1, "")], "") is None


class TestRoundChapterUrls:
    def test_real_rounds_link_and_only_forfeits_ride_along(self):
        event_rows = [
            {"UscfRound": 1.0, "ChapterURL": "u/1", "Forfeit": False},
            {"UscfRound": math.nan, "ChapterURL": "u/typed", "Forfeit": False},
        ]
        series_unmatched = [
            {"UscfRound": 2.0, "ChapterURL": "u/forfeit", "Forfeit": True},
            {"UscfRound": 3.0, "ChapterURL": "u/other-event", "Forfeit": False},
        ]
        assert round_chapter_urls(event_rows, series_unmatched) == {
            1: "u/1", 2: "u/forfeit",
        }
