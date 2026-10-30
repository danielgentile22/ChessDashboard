"""
payloads.meta
=============
The meta payload: who is signed in, the filter options and bounds, the
filter presets, per-source freshness, and the achievements the last Sync
earned.  Everything a client needs before it draws any screen.

``filter_bounds`` and ``preset_filters`` are also what the web filter drawer
uses, so the phone's options and presets can't drift from the web's.
"""
from __future__ import annotations

from collections.abc import Iterable
from datetime import date, datetime

import pandas as pd

from payloads.common import iso_date, iso_timestamp

ALL_COLORS = ["White", "Black"]
ALL_OUTCOMES = ["Win", "Draw", "Loss"]

# (id, label) in the web drawer's order.
PRESETS = [
    ("all", "All games"),
    ("last_20", "Last 20"),
    ("this_year", "This year"),
    ("white", "White only"),
    ("black", "Black only"),
    ("wins", "Wins only"),
]


def filter_bounds(df: pd.DataFrame) -> dict:
    """Option lists and ranges derived from the current Games."""
    terminations = sorted(
        [t for t in df["Termination"].dropna().unique() if str(t).strip()]
    ) if not df.empty else []
    events = sorted(
        [e for e in df["Event"].dropna().unique() if str(e).strip()]
    ) if not df.empty else []

    dated = df[df["Date_dt"].notna()] if not df.empty else df
    min_date = dated["Date_dt"].min().date().isoformat() if len(dated) else None
    max_date = dated["Date_dt"].max().date().isoformat() if len(dated) else None

    moves = df["FullMoves"].dropna() if not df.empty else pd.Series(dtype=float)
    min_mv = int(moves.min()) if not moves.empty else 1
    max_mv = int(moves.max()) if not moves.empty else 100

    return dict(terminations=terminations, events=events,
                min_date=min_date, max_date=max_date,
                min_mv=min_mv, max_mv=max_mv)


def preset_filters(preset: str, df: pd.DataFrame, today: date) -> dict:
    """The complete filter state a preset selects.

    Every preset is a complete starting point: reset all filters to
    "everything", then apply the preset's one specialization.  Dates default
    to None (no bound) so undated Games stay visible unless a preset narrows
    dates.
    """
    b = filter_bounds(df)
    state = dict(colors=list(ALL_COLORS), outcomes=list(ALL_OUTCOMES),
                 terminations=[], series=[], start=None, end=None,
                 min_moves=b["min_mv"], max_moves=b["max_mv"])
    if preset == "last_20":
        dated = df[df["Date_dt"].notna()] if not df.empty else df
        if not dated.empty:  # window over dated Games only (NaT sorts last)
            state["start"] = dated.sort_values("Date_dt").tail(20)["Date_dt"].min().date().isoformat()
    elif preset == "this_year":
        state["start"] = f"{today.year}-01-01"
    elif preset == "white":
        state["colors"] = ["White"]
    elif preset == "black":
        state["colors"] = ["Black"]
    elif preset == "wins":
        state["outcomes"] = ["Win"]
    return state


def build_meta(
    df: pd.DataFrame,
    *,
    player: str,
    session: dict,
    today: date,
    demo_mode: bool,
    lichess_synced_at: datetime | None,
    lichess_source: str,
    lichess_cached_at: datetime | None,
    uscf_enabled: bool,
    uscf_available: bool,
    uscf_synced_at: datetime | None,
    uscf_unavailable_since: str | None,
    new_achievements: Iterable,
) -> dict:
    """The meta payload over the unfiltered Games and the store's state."""
    b = filter_bounds(df)
    return {
        "player": player,
        "session": session,
        "demo_mode": demo_mode,
        "games_total": len(df),
        "filter_options": {
            "terminations": b["terminations"],
            "series": b["events"],
            "min_date": b["min_date"],
            "max_date": b["max_date"],
            "min_moves": b["min_mv"],
            "max_moves": b["max_mv"],
        },
        "presets": [{"id": pid, "label": label, "filters": preset_filters(pid, df, today)}
                    for pid, label in PRESETS],
        "freshness": {
            "lichess": {
                "synced_at": iso_timestamp(lichess_synced_at),
                "source": lichess_source,
                "cached_at": iso_timestamp(lichess_cached_at),
            },
            "uscf": {
                "enabled": uscf_enabled,
                "available": uscf_available,
                "synced_at": iso_timestamp(uscf_synced_at),
                "unavailable_since": uscf_unavailable_since,
            },
        },
        "new_achievements": [{
            "achievement_id": a.achievement_id,
            "kind": a.kind,
            "title": a.title,
            "detail": a.detail,
            "date": iso_date(a.date),
            "event_id": a.event_id,
            "event_name": a.event_name,
        } for a in new_achievements],
    }
