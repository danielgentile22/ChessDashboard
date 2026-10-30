"""
payloads.openings
=================
The Openings screen: the repertoire tree for both colors, the ECO family
breakdown, and the Top openings table.  Forfeits are left out of every
section by the cores (one forced move is not repertoire data).
"""
from __future__ import annotations

import pandas as pd

from payloads.common import game_id, iso_date
from pgn_stats_core import opening_summary, repertoire_tree


def _game_ref(ref: dict, dates: dict) -> dict:
    return {
        "game_id": game_id(ref["ChapterURL"]),
        "opponent": ref["Opponent"],
        "outcome": ref["Outcome"],
        "date": iso_date(dates.get(ref["ChapterURL"])),
    }


def _node(node: dict, dates: dict) -> dict:
    return {
        "san": node["san"],
        "ply": node["ply"],
        "game_count": node["games"],
        "win": node["win"],
        "draw": node["draw"],
        "loss": node["loss"],
        "score_pct": node["score_pct"],
        "underperforming": node["underperforming"],
        "games": [_game_ref(ref, dates) for ref in node["game_refs"]],
        "ended_here": [_game_ref(ref, dates) for ref in node["ended_here"]],
        "moves": [_node(child, dates) for child in node["moves"]],
    }


def _tree(df: pd.DataFrame, color: str, dates: dict) -> dict:
    tree = repertoire_tree(df, color)
    return {
        "color": tree["color"],
        "game_count": tree["games"],
        "score_pct": tree["score_pct"],
        "min_games": tree["min_games"],
        "moves": [_node(node, dates) for node in tree["moves"]],
    }


def _wdl(row: dict) -> dict:
    return {
        "game_count": int(row["Games"]),
        "win": int(row["Win"]),
        "draw": int(row["Draw"]),
        "loss": int(row["Loss"]),
        "win_rate_pct": float(row["WinRate"]),
    }


def build_openings(df: pd.DataFrame) -> dict:
    """The Openings payload over the filtered, lens-applied Games."""
    # The tree's Game refs carry the raw Date header; the contract's dates
    # are ISO, read from the parsed column by ChapterURL.
    dates = dict(zip(df["ChapterURL"], df["Date_dt"])) if not df.empty else {}
    families, openings = opening_summary(df)
    return {
        "games_count": len(df),
        "repertoire": {
            "white": _tree(df, "White", dates),
            "black": _tree(df, "Black", dates),
        },
        "eco_families": [
            {"eco_family": row["ECO_Family"], "family_name": row["FamilyName"], **_wdl(row)}
            for row in families.to_dict("records")
        ],
        "top_openings": [
            {"eco": row["ECO"], "opening": row["Opening"], **_wdl(row)}
            for row in openings.head(50).to_dict("records")
        ],
    }
