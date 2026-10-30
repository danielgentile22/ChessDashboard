"""
payloads.opponent
=================
One Scouting Report: the pre-game dossier on one opponent, over the filtered
Games.  ``uscf_identity`` is also what the web dossier renders, so the
then-vs-now rule lives once.
"""
from __future__ import annotations

from collections.abc import Mapping

import pandas as pd

from payloads.common import game_summary, whole_rating
from pgn_stats_core import scouting_report
from uscf_core import UscfProfile, uscf_member_url


def uscf_identity(games: pd.DataFrame, opponent: str, their_rating: int | None,
                  profiles: Mapping[str, UscfProfile]) -> dict | None:
    """The opponent's official USCF identity and their rating then vs now,
    or None when none of *games* (theirs, filtered) matched a USCF Game
    Record (ADR 0003).

    "Then" is *their_rating* (the lens-aware rating when last played); "now"
    is their current Regular rating from their profile.
    """
    matched = games[games["UscfOpponentId"] != ""]
    if matched.empty:
        return None
    member_id = str(matched.iloc[0]["UscfOpponentId"])
    profile = profiles.get(member_id)
    regular = profile.rating("R") if profile is not None else None
    now = whole_rating(regular.rating) if regular is not None else None
    return {
        "member_id": member_id,
        "name": str(matched.iloc[0]["UscfOpponentName"]) or opponent,
        "profile_url": uscf_member_url(member_id),
        "rating_when_last_played": their_rating,
        "current_rating": now,
        "rating_change": now - their_rating if now is not None and their_rating is not None else None,
    }


def build_opponent(df: pd.DataFrame, opponent: str, opponent_id: str,
                   profiles: Mapping[str, UscfProfile]) -> dict:
    """The Scouting Report on *opponent* over the filtered Games *df*."""
    report = scouting_report(df, opponent)
    games = df[df["Opponent"] == opponent] if not df.empty else df
    summaries = {row["ChapterURL"]: game_summary(row) for row in games.to_dict("records")}

    def _openings(rows: list[dict]) -> list[dict]:
        return [{"eco": o["ECO"], "opening": o["Opening"], "games": int(o["Games"]),
                 "win": int(o["Win"]), "draw": int(o["Draw"]), "loss": int(o["Loss"])}
                for o in rows]

    return {
        "games_count": len(games),
        "opponent_id": opponent_id,
        "opponent": opponent,
        "uscf_identity": (uscf_identity(games, opponent, report["their_rating"], profiles)
                          if report["total"] else None),
        "record": {
            "games": report["total"],
            "win": report["win"],
            "draw": report["draw"],
            "loss": report["loss"],
            "score_points": report["win"] + 0.5 * report["draw"],
            "score": report["score"],
        },
        "their_rating": report["their_rating"],
        "rating_gap": report["rating_gap"],
        "games": [summaries[row["ChapterURL"]] for row in report["timeline"]],
        "openings_as_white": _openings(report["openings_as_white"]),
        "openings_as_black": _openings(report["openings_as_black"]),
        "terminations": [{"termination": t["Termination"], "games": int(t["Games"])}
                         for t in report["terminations"]],
        "lessons": [{"text": lesson["Lesson"], "game": summaries[lesson["ChapterURL"]]}
                    for lesson in report["lessons"]],
    }
