"""
tests/test_payloads_overview.py
===============================
The Overview payload builder (``payloads.overview``): the pieces the sample
data doesn't reach through the route (the weakness Tag source, fire and
cold, undated milestones, the USCF card's degraded states).
"""
from __future__ import annotations

from datetime import date

import pandas as pd

from payloads.overview import (
    _milestone,
    _top_weakness,
    form_indicator,
    milestone_timeline,
    uscf_card,
)
from uscf_core import LiveRatingPoint, UscfAchievement, UscfProfile, UscfRating


def _losses_tagged(tag: str, sources: list[str]) -> pd.DataFrame:
    """Three Losses carrying *tag*, each written by the matching source."""
    n = len(sources)
    dates = pd.date_range("2024-01-01", periods=n, freq="W")
    return pd.DataFrame({
        "Outcome": ["Loss"] * n,
        "Tags": [[tag]] * n,
        "TagSources": [{tag: s} for s in sources],
        "Date_dt": dates,
        "Index": range(1, n + 1),
        "ChapterURL": [f"https://lichess.org/study/x/ch{i:04d}" for i in range(1, n + 1)],
        "Opponent": ["Someone"] * n,
    })


class TestTopWeakness:
    def test_engine_tag_when_every_game_behind_it_is_engine_emitted(self):
        top = _top_weakness(_losses_tagged("tactical", ["engine"] * 3))
        assert top["tag"] == {"name": "tactical", "source": "engine"}
        assert top["game_ids"] == ["ch0001", "ch0002", "ch0003"]

    def test_mine_when_any_game_behind_it_was_hand_tagged(self):
        top = _top_weakness(_losses_tagged("tactical", ["engine", "mine", "engine"]))
        assert top["tag"]["source"] == "mine"

    def test_silent_below_threshold(self):
        assert _top_weakness(_losses_tagged("tactical", ["mine"] * 2)) is None


class TestFormIndicator:
    def test_fire_from_two_wins_blazing_from_five(self):
        assert form_indicator(2, 0) == {"kind": "fire", "count": 2, "blazing": False}
        assert form_indicator(5, 0)["blazing"] is True

    def test_cold_from_three_losses(self):
        assert form_indicator(0, 2)["kind"] == "none"
        assert form_indicator(0, 3) == {"kind": "cold", "count": 3, "blazing": False}

    def test_quiet_otherwise(self):
        assert form_indicator(1, 0) == {"kind": "none", "count": 0, "blazing": False}


class TestMilestones:
    def test_undated_entries_sort_last_and_have_no_date(self, df):
        undated = UscfAchievement("a1", "award", "An award", "", None, "e1", "E")
        dated = UscfAchievement("a2", "award", "Another", "", date(2024, 1, 6), "e2", "E")
        timeline = milestone_timeline(df, [undated, dated], start=None, end=None)
        assert timeline[-1]["description"] == "An award, E"
        # Same day as the first Game: the Game milestones come first
        same_day = [m for m in timeline if m["date"] == "2024-01-06"]
        assert same_day[-1]["kind"] == "uscf"
        assert _milestone(timeline[-1])["date"] is None
        assert _milestone({"kind": "win", "date": "2024.??.??", "game_num": 3,
                           "chapter_url": "https://lichess.org/study/x/ch0003",
                           "description": "d"})["date"] is None

    def test_a_game_milestone_points_at_its_game(self, df):
        entry = _milestone(milestone_timeline(df, [], start=None, end=None)[0])
        assert entry["game_id"] and entry["event_id"] == ""


PROFILE = UscfProfile(
    member_id="1", name="A Player", state="", national_rank=None, state_rank=None,
    ratings=(UscfRating("R", 1500, False, None, 1300),),
    membership_status="Active", membership_expires=date(2026, 7, 1),
)


class TestUscfCard:
    def test_unavailable_carries_the_reason(self):
        card = uscf_card(enabled=True, profile=None, failure="timed out",
                         unavailable_since=None, live_series=[], today=date(2026, 6, 15))
        assert card == {"state": "unavailable", "profile": None,
                        "unavailable_reason": "timed out", "unavailable_since": None}

    def test_live_rating_is_whole_and_the_alert_uses_today(self):
        live = [LiveRatingPoint("e", "E", "S", date(2026, 1, 1), None, 1571.6)]
        card = uscf_card(enabled=True, profile=PROFILE, failure="",
                         unavailable_since="USCF unavailable since x",
                         live_series=live, today=date(2026, 6, 15))
        profile = card["profile"]
        assert profile["live_rating"] == 1572
        assert profile["official_rating"] == 1500
        assert profile["quick"] is None
        assert "expires in 16 days" in profile["membership_alert"]
        assert card["unavailable_since"] == "USCF unavailable since x"
