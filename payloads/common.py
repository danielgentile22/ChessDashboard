"""
payloads.common
===============
The shapes every screen payload shares: the Game summary row, Tags with their
source, whole-number ratings, ISO dates, and the opaque Game ID.

Display rules live here so no screen re-derives them: ratings are whole
numbers (the Live series keeps decimals only internally), every Tag carries
its source, and enrichment fields are always present (an unmatched Game is
``"unmatched"``, never a missing key).
"""
from __future__ import annotations

import math
from collections.abc import Iterable, Mapping
from datetime import date, datetime
from typing import Any

import pandas as pd

from pgn_stats_core import chapter_id

MINE = "mine"
ENGINE = "engine"


def game_id(chapter_url: str) -> str:
    """The opaque Game ID for a ChapterURL: stable across Syncs, and the same
    id the web's ``/game/<id>`` route uses."""
    return chapter_id(chapter_url)


def whole_rating(value: Any) -> int | None:
    """A rating as a whole number, or None when unknown (blank, NaN, or the
    0 the parser uses for an unrated header)."""
    if value is None or isinstance(value, bool):
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if math.isnan(number) or number <= 0:
        return None
    return int(round(number))


def iso_date(value: Any) -> str | None:
    """A date or timestamp as ``YYYY-MM-DD``, or None when undated."""
    if value is None or (not isinstance(value, str) and pd.isna(value)):
        return None
    if isinstance(value, (datetime, date)):
        return value.isoformat()[:10]
    return None


def iso_timestamp(value: datetime | None) -> str | None:
    """A UTC timestamp as ISO 8601 with a ``Z``, or None when never."""
    if value is None:
        return None
    return value.isoformat().replace("+00:00", "Z")


# An unknown round or move count parses the same way as an unrated header.
optional_int = whole_rating


def tags(names: Iterable[str], sources: Mapping[str, str] | None) -> list[dict]:
    """A Game's Tags with who wrote each: ``mine`` unless the Game's
    ``TagSources`` map says the engine emitted it (the same rule as
    ``components.tag_chips``)."""
    sources = sources or {}
    return [{"name": name, "source": ENGINE if sources.get(name) == ENGINE else MINE}
            for name in names]


def uscf_status(matched_by: str, forfeit: bool, conflict: bool) -> str:
    """The Game's USCF status, the same precedence as the web Games table."""
    if forfeit:
        return "forfeit"
    if conflict:
        return "conflict"
    return {"id": "matched_by_id", "name": "matched_by_name"}.get(matched_by, "unmatched")


def game_summary(row: Mapping) -> dict:
    """One Game as the shared list row (``GameSummary`` in the contract)."""
    return {
        "game_id": game_id(row["ChapterURL"]),
        "chapter_url": row["ChapterURL"],
        "date": iso_date(row["Date_dt"]),
        "series": row["Event"] or "",
        "round": optional_int(row["RoundNum"]),
        "opponent": row["Opponent"],
        "opponent_rating": whole_rating(row["OpponentRatingNum"]),
        "color": row["Color"],
        "player_rating": whole_rating(row["PlayerRatingNum"]),
        "outcome": row["Outcome"],
        "result": row["Result"],
        "termination": row["Termination"],
        "moves": optional_int(row["FullMoves"]),
        "eco": row["ECO"] or "",
        "opening": row["Opening"] or "",
        "has_lesson": bool(row["Lessons"]),
        "tags": tags(row["Tags"], row["TagSources"]),
        "uscf_status": uscf_status(row["UscfMatchedBy"], bool(row["Forfeit"]),
                                   bool(row["UscfColorConflict"])),
    }


def game_summaries(df: pd.DataFrame) -> list[dict]:
    """Every Game in *df* as a summary row, in *df*'s order."""
    if df.empty:
        return []
    return [game_summary(row) for row in df.to_dict("records")]
