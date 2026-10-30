"""
payloads.trends
===============
The Trends payload: the activity calendar, the rating chart (dual-line
Official/Live, or typed header ratings when USCF was never reached), win
rate, activity, game length, time controls, the fatigue check, and upsets.

``typed_rating_points`` is also what the web's fallback rating chart draws,
so the phone's trend line can't drift from the web's.
"""
from __future__ import annotations

from collections.abc import Sequence

import numpy as np
import pandas as pd

from payloads.common import game_id, game_summary, iso_date, whole_rating
from pgn_stats_core import (
    activity_data,
    daily_activity,
    game_length_data,
    player_rating_over_time,
    round_performance,
    time_control_summary,
    upset_tracker,
    win_rate_over_time,
)
from uscf_core import LiveRatingPoint, OfficialRatingPoint, rating_trend_series

_FINISHED = ["Win", "Draw", "Loss"]


def typed_rating_points(df: pd.DataFrame) -> pd.DataFrame:
    """The Studies' typed ratings per day (the day's last Game) plus a linear
    trend over point index.  Columns: Date_dt, PlayerRating, Trend (NaN on
    every row when there are fewer than 3 points)."""
    pr = player_rating_over_time(df).copy()
    pr["Trend"] = np.nan
    if len(pr) >= 3:
        x = np.arange(len(pr))
        coeffs = np.polyfit(x, pr["PlayerRating"].to_numpy(dtype=float), 1)
        # Rounded so the value is the same on every platform's float math
        pr["Trend"] = np.round(np.polyval(coeffs, x), 2)
    return pr


def _calendar(df: pd.DataFrame) -> list[dict]:
    daily = daily_activity(df)
    if daily.empty:
        return []
    # The same Games daily_activity counts, kept per Game for the day's detail
    played = df[df["Date_dt"].notna() & df["Outcome"].isin(_FINISHED) & ~df["Forfeit"]]
    played = played.sort_values(["Date_dt", "Index"])
    games_by_day: dict[pd.Timestamp, list[dict]] = {}
    for row in played.to_dict("records"):
        games_by_day.setdefault(row["Date_dt"].normalize(), []).append({
            "game_id": game_id(row["ChapterURL"]),
            "outcome": row["Outcome"],
            "opponent": row["Opponent"],
        })

    years = []
    for year, year_daily in daily.groupby(daily["Date_dt"].dt.year):
        years.append({
            "year": int(year),
            "games": int(year_daily["Games"].sum()),
            "wins": int(year_daily["Win"].sum()),
            "losses": int(year_daily["Loss"].sum()),
            "days": [{
                "date": iso_date(day["Date_dt"]),
                "games": int(day["Games"]),
                "win": int(day["Win"]),
                "draw": int(day["Draw"]),
                "loss": int(day["Loss"]),
                "net": int(day["Net"]),
                "game_list": games_by_day.get(day["Date_dt"], []),
            } for day in year_daily.to_dict("records")],
        })
    return sorted(years, key=lambda y: -y["year"])


def _rating_chart(
    df: pd.DataFrame,
    official_series: Sequence[OfficialRatingPoint],
    live_series: Sequence[LiveRatingPoint],
    *,
    lens: str,
    start: str | None,
    end: str | None,
) -> dict:
    chart: dict = {"mode": "typed", "emphasized": lens, "official": [], "live": [], "typed": []}
    if not official_series and not live_series:
        # USCF never reached or not configured: the Studies' own numbers
        chart["typed"] = [{
            "date": iso_date(p["Date_dt"]),
            "rating": whole_rating(p["PlayerRating"]),
            "trend": None if pd.isna(p["Trend"]) else float(p["Trend"]),
        } for p in typed_rating_points(df).to_dict("records")]
        return chart

    official, live = rating_trend_series(list(official_series), list(live_series),
                                         date_start=start, date_end=end)
    chart["mode"] = "uscf"
    chart["official"] = [{"month": p.month.isoformat(), "rating": whole_rating(p.rating)}
                         for p in official]
    chart["live"] = [{
        "end_date": p.end_date.isoformat(),
        "rating": whole_rating(p.post),
        "pre_rating": whole_rating(p.pre),
        "event_id": p.event_id,
        "event_name": p.event_name,
        "section_name": p.section_name,
    } for p in live]
    return chart


def _upsets(df: pd.DataFrame) -> dict:
    upsets = upset_tracker(df)
    by_url = {row["ChapterURL"]: row for row in df.to_dict("records")} if not df.empty else {}

    def _rows(rows: list[dict]) -> list[dict]:
        return [{"game": game_summary(by_url[r["ChapterURL"]]), "margin": int(r["Margin"])}
                for r in rows]

    return {"giant_kills": _rows(upsets["wins"]), "upset_losses": _rows(upsets["losses"])}


def build_trends(
    df: pd.DataFrame,
    *,
    official_series: Sequence[OfficialRatingPoint],
    live_series: Sequence[LiveRatingPoint],
    lens: str,
    start: str | None,
    end: str | None,
) -> dict:
    """The Trends payload over the filtered Games.  The rating series are the
    store's full USCF series; only *start*/*end* trim them, and *lens* only
    picks which line is emphasized."""
    win_rate = win_rate_over_time(df)
    monthly, weekday = activity_data(df)
    lengths, averages = game_length_data(df)
    controls = time_control_summary(df)
    rounds = round_performance(df)
    return {
        "games_count": len(df),
        "calendar": _calendar(df),
        "rating_chart": _rating_chart(df, official_series, live_series,
                                      lens=lens, start=start, end=end),
        "win_rate": [{
            "date": iso_date(p["Date_dt"]),
            "win_rate_pct": float(p["WinRate"]),
            "cum_wins": int(p["CumWins"]),
            "cum_games": int(p["CumGames"]),
        } for p in win_rate.to_dict("records")],
        "games_per_month": [{
            "year_month": m["YearMonth"],
            "games": int(m["Games"]),
            "wins": int(m["Win"]),
            "win_rate_pct": float(m["WinRate"]),
        } for m in monthly.to_dict("records")],
        "win_rate_by_weekday": [{
            "day_of_week": d["DayOfWeek"],
            "games": int(d["Games"]),
            "wins": int(d["Win"]),
            "win_rate_pct": float(d["WinRate"]),
        } for d in weekday.to_dict("records")],
        "game_lengths": [{"moves": int(g["FullMoves"]), "outcome": g["Outcome"]}
                         for g in lengths.to_dict("records")],
        "average_length": {
            "win": averages.get("Win"),
            "draw": averages.get("Draw"),
            "loss": averages.get("Loss"),
        },
        "time_controls": [{
            "time_control": t["TimeControl"],
            "speed": t["Speed"],
            "minutes": None if pd.isna(t["Minutes"]) else float(t["Minutes"]),
            "games": int(t["Games"]),
            "win": int(t["Win"]),
            "draw": int(t["Draw"]),
            "loss": int(t["Loss"]),
            "win_rate_pct": float(t["WinRate"]),
        } for t in controls.to_dict("records")],
        "rounds": [{
            "round": int(r["Round"]),
            "games": int(r["Games"]),
            "win": int(r["Win"]),
            "draw": int(r["Draw"]),
            "loss": int(r["Loss"]),
            "win_rate_pct": float(r["WinRate"]),
            "score_pct": float(r["ScorePct"]),
            "reliable": bool(r["Reliable"]),
        } for r in rounds.to_dict("records")],
        "upsets": _upsets(df),
    }
