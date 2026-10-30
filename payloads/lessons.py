"""
payloads.lessons
================
The Lessons screen: every Lesson with its Game, the Tag counts (split by who
wrote each Tag), recurring-weakness callouts, the opponent picker, the
pre-game review queue, and the Coach's Notes feed.

The list, Tag counts, and callouts honor the global filters; the picker, the
review queue, and the Coach's Notes are built from the whole archive, as on
the web.
"""
from __future__ import annotations

import pandas as pd

from payloads.common import game_id, game_summary
from payloads.opponent_ids import opponent_ids, resolve_opponent
from pgn_stats_core import lessons_table, recurring_weaknesses, review_queue, tag_counts

# review_queue priority -> the contract's reason_kind
REASON_KINDS = {0: "recurring_weakness", 1: "facing_opponent", 2: "recent"}


def lesson_tag_counts(df: pd.DataFrame) -> list[dict]:
    """The Tag chips over *df*, canonical taxonomy first, with the source split."""
    return [{"name": t["tag"], "canonical": t["canonical"], "count": t["count"],
             "mine_count": t["mine"], "engine_count": t["engine"]}
            for t in tag_counts(df)]


def _summaries(df: pd.DataFrame) -> dict[str, dict]:
    """Every Game in *df* as a summary row, keyed by ChapterURL."""
    return {row["ChapterURL"]: game_summary(row) for row in df.to_dict("records")}


def _weakness(callout: dict) -> dict:
    return {
        "tag": callout["tag"],
        "loss_count": callout["loss_count"],
        "window_losses": callout["window_losses"],
        "stat": callout["stat"],
        "window": callout["window"],
        "severity": callout["severity"],
        "games": [{"game_id": game_id(url)} for url in callout["chapter_urls"] if url],
    }


def _review(archive: pd.DataFrame, summaries: dict[str, dict],
            opponent_id: str | None, opponent: str | None) -> dict:
    return {
        "opponent_id": opponent_id,
        "opponent": opponent,
        "cards": [{
            "reason_kind": REASON_KINDS[card["priority"]],
            "reason": card["reason"],
            "text": card["Lesson"],
            "game": summaries[card["ChapterURL"]],
        } for card in review_queue(archive, opponent=opponent)],
    }


def build_lessons(
    df: pd.DataFrame,
    archive: pd.DataFrame,
    *,
    tags: list[str],
    opponent_id: str | None,
    review: bool,
    coach_notes: list[dict],
) -> dict:
    """The Lessons payload.

    *df* is the filtered Games, *archive* the whole archive (lens applied),
    *coach_notes* the store's Coach's Notes feed.  *tags* and *opponent_id*
    narrow only the Lessons list; an *opponent_id* that names no opponent
    matches nothing.
    """
    ids = opponent_ids(archive)
    opponent = resolve_opponent(archive, opponent_id) if opponent_id else None
    canonical_id = ids[opponent] if opponent else None
    filtered = _summaries(df)
    everything = _summaries(archive)

    if opponent_id and opponent is None:
        lessons: list[dict] = []
    else:
        lessons = lessons_table(df, tags=tags or None, opponent=opponent).to_dict("records")

    with_lessons = set(archive.loc[archive["Lessons"].map(bool), "Opponent"]) if not archive.empty else set()

    return {
        "games_count": len(df),
        "lessons": [{"text": row["Lesson"], "game": filtered[row["ChapterURL"]]}
                    for row in lessons],
        "tag_counts": lesson_tag_counts(df),
        "recurring_weaknesses": [_weakness(c) for c in recurring_weaknesses(df)],
        "lessons_opponents": [{"opponent_id": ids[name], "opponent": name}
                              for name in sorted(ids) if name in with_lessons],
        "review": _review(archive, everything, canonical_id, opponent) if review else None,
        "coach_notes": [{
            "text": note["text"],
            "move_number": note["move_number"],
            "game": everything[note["chapter_url"]],
        } for note in coach_notes if note["chapter_url"] in everything],
    }
