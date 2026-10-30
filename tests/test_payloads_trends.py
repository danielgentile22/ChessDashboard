"""
tests/test_payloads_trends.py
=============================
The Trends payload builder (``payloads.trends``): the typed-rating trend line
the web chart shares, and the calendar's per-Game day detail.
"""
from __future__ import annotations

import pandas as pd

from payloads.trends import _calendar, typed_rating_points


def _rated(ratings: list[int]) -> pd.DataFrame:
    n = len(ratings)
    return pd.DataFrame({
        "Date_dt": pd.date_range("2024-01-01", periods=n, freq="D"),
        "PlayerRatingNum": [float(r) for r in ratings],
        "Index": range(1, n + 1),
    })


class TestTypedRatingPoints:
    def test_trend_is_the_least_squares_line(self):
        pr = typed_rating_points(_rated([1500, 1510, 1520, 1530]))
        assert pr["Trend"].tolist() == [1500.0, 1510.0, 1520.0, 1530.0]

    def test_no_trend_below_three_points(self):
        pr = typed_rating_points(_rated([1500, 1510]))
        assert pr["Trend"].isna().all()

    def test_empty(self):
        assert typed_rating_points(pd.DataFrame()).empty


class TestCalendar:
    def test_a_day_lists_its_played_games_in_order(self, df):
        frame = df.copy()
        day = frame["Date_dt"].dropna().iloc[0]
        frame["Forfeit"] = False
        same_day = frame.index[frame["Date_dt"] == day]
        frame.loc[same_day[0], "Forfeit"] = True  # a no-show isn't on the calendar

        days = [d for y in _calendar(frame) for d in y["days"]
                if d["date"] == day.date().isoformat()]
        assert len(days) == 1
        assert days[0]["games"] == len(same_day) - 1 == len(days[0]["game_list"])


def test_the_web_fallback_chart_draws_the_same_trend(api_lichess_only):
    """With USCF off the web rating chart is the typed points plus the trend
    line the API serves."""
    from pages.trends import update_rating

    fig = update_rating([], [], [], None, None, [], None)
    rating, trend = fig.data
    api_trend = [p["trend"] for p in
                 api_lichess_only.get("/api/v1/trends")["rating_chart"]["typed"]]
    assert list(trend.y) == api_trend
    assert len(rating.y) == len(api_trend)
