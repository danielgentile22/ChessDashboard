"""
payloads.analysis
=================
The Analysis screen: the Error Profile across every analysed Game.

Unfiltered and unlensed, like the web page: the caller passes the full store
DataFrame and the rating overlay is the player's typed rating per Game.  Every
aggregate comes from ``analysis_trends`` / ``engine_analysis_core``, the same
functions behind the web page's ``data`` accessors.
"""
from __future__ import annotations

import pandas as pd

from analysis_trends import (
    accuracy_trend,
    awaiting_analysis,
    mistake_move_histogram,
    mistake_type_trend,
    phase_type_matrix,
)
from engine_analysis_core import mistake_type_distribution
from payloads.common import game_id, iso_date, whole_rating

_PHASES = ["opening", "middlegame", "endgame"]


def _has_analysis(df: pd.DataFrame) -> bool:
    return not df.empty and bool(df["Analyzed"].astype(bool).any())


def _phase_rows(matrix: pd.DataFrame) -> list[dict]:
    """The three Phase rows, zero-filled, or [] when there are no mistakes."""
    if matrix.empty:
        return []
    full = matrix.reindex(index=_PHASES, columns=["tactical", "positional"], fill_value=0)
    return [{"phase": phase, "tactical": int(row["tactical"]),
             "positional": int(row["positional"])}
            for phase, row in full.iterrows()]


def build_analysis(df: pd.DataFrame) -> dict:
    """The Analysis screen over the store's Games (``AnalysisPayload``)."""
    distribution = mistake_type_distribution(df["Analysis"] if not df.empty else [])
    return {
        "has_analysis": _has_analysis(df),
        "mistake_type_distribution": {"tactical": distribution["tactical"],
                                      "positional": distribution["positional"]},
        "accuracy_trend": [{
            "game_id": game_id(row["ChapterURL"]),
            "date": iso_date(row["Date_dt"]),
            "accuracy": round(float(row["Accuracy"]), 2),
            "rating": whole_rating(row["Rating"]),
            "opponent": row["Opponent"],
        } for row in accuracy_trend(df).to_dict("records")],
        "mistake_type_trend": [{
            "game_id": game_id(row["ChapterURL"]),
            "date": iso_date(row["Date_dt"]),
            "tactical": int(row["Tactical"]),
            "positional": int(row["Positional"]),
            "rating": whole_rating(row["Rating"]),
            "opponent": row["Opponent"],
        } for row in mistake_type_trend(df).to_dict("records")],
        "phase_type_matrix": _phase_rows(phase_type_matrix(df)),
        "mistake_move_histogram": [
            {"move_number": int(row["MoveNumber"]), "count": int(row["Count"])}
            for row in mistake_move_histogram(df).to_dict("records")],
        "awaiting_analysis": [{
            "game_id": game_id(row["ChapterURL"]),
            # The Chapter name, falling back as the web row does.
            "name": str(row["ChapterName"] or row["Opponent"] or "Game"),
            "date": iso_date(row["Date_dt"]),
            "chapter_url": row["ChapterURL"],
        } for row in awaiting_analysis(df).to_dict("records")],
    }
