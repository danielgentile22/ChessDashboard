"""
payloads.sync
=============
What a successful Sync reports: the web toast (new Games, Studies that
couldn't be fetched, per-source freshness) and the celebration banner
(personal bests the new Games set, official USCF achievements first seen).

Pure: the caller runs the Sync and passes its outcome, the pre- and post-Sync
Games, and the store's freshness facts.
"""
from __future__ import annotations

from datetime import datetime

import pandas as pd

from payloads.common import game_id, iso_date, iso_timestamp
from pgn_stats_core import milestone_deltas
from uscf_core import UscfAchievement


def _new_game(game: dict) -> dict:
    return {
        "game_id": game_id(game["ChapterURL"]),
        "opponent": game["Opponent"],
        "outcome": game["Outcome"],
        "result": game["Result"],
        "date": iso_date(game["Date_dt"]),
    }


def _achievement(a: UscfAchievement) -> dict:
    return {
        "achievement_id": a.achievement_id,
        "kind": a.kind,
        "title": a.title,
        "detail": a.detail,
        "date": iso_date(a.date),
        "rated_event_id": a.event_id,
        "rated_event_name": a.event_name,
    }


def build_sync(
    *,
    status: str,
    new_games: list[dict],
    failures: list[tuple[str, str]],
    before: pd.DataFrame,
    after: pd.DataFrame,
    new_achievements: list[UscfAchievement],
    synced_at: datetime | None,
    uscf_synced_at: datetime | None,
    uscf_unavailable_since: str | None,
) -> dict:
    """The Sync outcome (``SyncPayload``).  ``already_running`` did nothing,
    so it reports no new Games, bests, or achievements."""
    ran = status == "success"
    return {
        "status": status,
        "new_games": [_new_game(g) for g in new_games] if ran else [],
        "milestones": [{
            "kind": d["kind"],
            "old": int(d["old"]),
            "new": int(d["new"]),
            "description": d["description"],
        } for d in milestone_deltas(before, after)] if ran else [],
        "new_achievements": [_achievement(a) for a in new_achievements] if ran else [],
        "failures": [{"study_id": study_id, "reason": reason}
                     for study_id, reason in failures] if ran else [],
        "synced_at": iso_timestamp(synced_at),
        "uscf_synced_at": iso_timestamp(uscf_synced_at),
        "uscf_unavailable_since": uscf_unavailable_since,
    }
