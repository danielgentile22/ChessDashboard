"""
payloads.overview
=================
The Overview payload: KPIs, the USCF profile card, the current Streak and
last-20 form, Win / Draw / Loss, how Games ended, the top recurring weakness,
and the milestone timeline.

Everything follows the filters and lens except the USCF card, which follows
Syncs.  ``milestone_timeline`` and ``form_indicator`` are also what the web
Overview and header use, so the phone's timeline and fire can't drift from
the web's.
"""
from __future__ import annotations

import re
from collections.abc import Iterable, Sequence
from datetime import date

import pandas as pd

from payloads.common import ENGINE, MINE, game_id, whole_rating
from pgn_stats_core import (
    compute_milestones,
    is_engine_tag,
    kpi_stats,
    recurring_weaknesses,
    streaks,
    termination_counts,
    win_draw_loss_counts,
)
from uscf_core import (
    LiveRatingPoint,
    UscfAchievement,
    UscfProfile,
    UscfRating,
    achievement_milestones,
    membership_alert,
)

_ISO_DAY = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def milestone_timeline(
    df: pd.DataFrame,
    achievements: Iterable[UscfAchievement],
    *,
    start: str | None,
    end: str | None,
) -> list[dict]:
    """Game milestones and official achievements on one timeline.

    Achievements aren't Games, so only the date range applies to them, never
    the Game filters.  Chronological across both kinds; undated entries last;
    Game milestones break date ties by game number, achievements go after.
    """
    ms = compute_milestones(df)
    ms += achievement_milestones(list(achievements), date_start=start, date_end=end)

    def _chronological(m: dict):
        # PGN-style dates ('2026.05.01') compare correctly against ISO ones
        date_str = (m["date"] or "").replace(".", "-")
        return (date_str == "", date_str, m["game_num"] is None, m["game_num"] or 0)

    return sorted(ms, key=_chronological)


def form_indicator(win_streak: int, loss_streak: int) -> dict:
    """The header's fire / cold indicator for the current Streak.

    Fire at a win Streak of 2+ (blazing at 5+); cold at a loss Streak of 3+
    when there is no fire.
    """
    if win_streak >= 2:
        return {"kind": "fire", "count": win_streak, "blazing": win_streak >= 5}
    if loss_streak >= 3:
        return {"kind": "cold", "count": loss_streak, "blazing": False}
    return {"kind": "none", "count": 0, "blazing": False}


def _rating_entry(entry: UscfRating | None) -> dict | None:
    if entry is None:
        return None
    return {
        "rating": whole_rating(entry.rating),
        "is_provisional": entry.is_provisional,
        "games_played": entry.games_played,
        "floor": whole_rating(entry.floor),
    }


def uscf_card(
    *,
    enabled: bool,
    profile: UscfProfile | None,
    failure: str,
    unavailable_since: str | None,
    live_series: Sequence[LiveRatingPoint],
    today: date,
) -> dict:
    """The USCF profile card: disabled, unavailable, or the profile."""
    if not enabled:
        return {"state": "disabled", "profile": None,
                "unavailable_reason": "", "unavailable_since": None}
    if profile is None:
        return {"state": "unavailable", "profile": None,
                "unavailable_reason": failure, "unavailable_since": None}
    regular = profile.rating("R")
    return {
        "state": "ok",
        "profile": {
            "member_id": profile.member_id,
            "name": profile.name,
            "state": profile.state,
            "membership_status": profile.membership_status,
            "membership_expires": (profile.membership_expires.isoformat()
                                   if profile.membership_expires else None),
            "membership_alert": membership_alert(profile, today=today),
            "official_rating": whole_rating(regular.rating) if regular else None,
            "live_rating": whole_rating(live_series[-1].post) if live_series else None,
            "regular": _rating_entry(regular),
            "quick": _rating_entry(profile.rating("Q")),
            "online_regular": _rating_entry(profile.rating("OR")),
            "national_rank": profile.national_rank,
            "state_rank": profile.state_rank,
        },
        "unavailable_reason": "",
        "unavailable_since": unavailable_since,
    }


def _kpis(df: pd.DataFrame) -> dict:
    k = kpi_stats(df)
    return {
        "win_pct": k["win_pct"],
        "draw_pct": k["draw_pct"],
        "loss_pct": k["loss_pct"],
        "rating": whole_rating(k["current_rating"]),
        "peak_rating": whole_rating(k["peak_rating"]),
        "performance_rating": whole_rating(k["performance_rating"]),
        "longest_win_streak": k["longest_win_streak"],
        "unique_opponents": k["unique_opponents"],
        # The core's placeholder for "no opening" is a dash; the payload says ""
        "favorite_opening": "" if k["favorite_opening"] == "—" else k["favorite_opening"],
    }


def _streak(df: pd.DataFrame) -> dict:
    s = streaks(df)
    outcome = s["current_streak_outcome"]
    count = s["current_streak_same_outcome"]
    return {
        "last_20": s["last_20"],
        "longest_unbeaten": s["longest_streak_no_loss"],
        "longest_win_streak": s["longest_streak_wins_only"],
        "current_outcome": None if outcome == "N/A" else outcome,
        "current_count": count,
        "indicator": form_indicator(count if outcome == "Win" else 0,
                                    count if outcome == "Loss" else 0),
    }


def _top_weakness(df: pd.DataFrame) -> dict | None:
    callouts = recurring_weaknesses(df)
    if not callouts:
        return None
    top = callouts[0]
    behind = df[df["ChapterURL"].isin(top["chapter_urls"])]
    engine_only = not behind.empty and all(
        is_engine_tag(top["tag"], sources) for sources in behind["TagSources"])
    return {
        "tag": {"name": top["tag"], "source": ENGINE if engine_only else MINE},
        "loss_count": top["loss_count"],
        "window_losses": top["window_losses"],
        "stat": top["stat"],
        "window": top["window"],
        "severity": top["severity"],
        "game_ids": [game_id(url) for url in top["chapter_urls"]],
    }


def _milestone(m: dict) -> dict:
    is_uscf = m["kind"] == "uscf"
    return {
        "kind": m["kind"],
        "date": m["date"] if _ISO_DAY.match(m["date"] or "") else None,
        "game_num": m["game_num"],
        "game_id": None if is_uscf else game_id(m["chapter_url"]),
        "event_id": (m.get("event_id") or "") if is_uscf else "",
        "description": m["description"],
    }


def build_overview(
    df: pd.DataFrame,
    *,
    uscf_card: dict,
    achievements: Iterable[UscfAchievement],
    start: str | None,
    end: str | None,
) -> dict:
    """The Overview payload over the filtered Games.  *uscf_card* comes from
    :func:`uscf_card`; *start*/*end* are the date filter, the only one the
    achievements on the timeline obey."""
    counts = win_draw_loss_counts(df)
    terminations = termination_counts(df)
    return {
        "games_count": len(df),
        "kpis": _kpis(df),
        "uscf_card": uscf_card,
        "top_weakness": _top_weakness(df),
        "streak": _streak(df),
        "outcome_counts": {
            "win": int(counts["Win"]),
            "draw": int(counts["Draw"]),
            "loss": int(counts["Loss"]),
            "unknown": int(counts["Unknown"]),
        },
        "terminations": [{"termination": str(t), "games": int(n)}
                         for t, n in zip(terminations["Termination"],
                                         terminations["Games"], strict=True)],
        "milestones": [_milestone(m)
                       for m in milestone_timeline(df, achievements, start=start, end=end)],
    }
