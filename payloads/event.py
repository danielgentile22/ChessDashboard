"""
payloads.event
==============
One Rated Event: the web's Rated Event card plus its crosstables, keyed by
USCF event ID.  If its Games sit under more than one Series, this view
combines them.  Facts derived from Games follow the filters; the crosstables
are member-level USCF facts, never filtered, only selected by the Sections
played.
"""
from __future__ import annotations

import pandas as pd

from payloads.common import game_id, whole_rating
from payloads.events import (
    Standings,
    performance_by_event,
    rated_event_facts,
    rating_change,
    round_chapter_urls,
    rows_by_url,
    section_placement,
)
from uscf_core import (
    LiveRatingPoint,
    RoundOutcome,
    StandingEntry,
    UscfEvent,
    rated_event_summary,
)


def _round(outcome: RoundOutcome, urls_by_round: dict[int, str]) -> dict:
    url = urls_by_round.get(outcome.round_number)
    return {
        "round_number": outcome.round_number,
        "outcome": outcome.outcome,
        "color": outcome.color,
        "opponent_member_id": outcome.opponent_member_id,
        "opponent_name": outcome.opponent_name,
        "game_id": game_id(url) if url else None,
    }


def _crosstable_row(entry: StandingEntry, member_id: str,
                    urls_by_round: dict[int, str]) -> dict:
    is_player = bool(member_id) and entry.member_id == member_id
    links = urls_by_round if is_player else {}
    return {
        "ordinal": entry.ordinal,
        "member_id": entry.member_id,
        "name": entry.name,
        "is_player": is_player,
        "pre_rating": whole_rating(entry.pre_rating),
        "post_rating": whole_rating(entry.post_rating),
        "rating_change": rating_change(entry.pre_rating, entry.post_rating),
        "score": entry.score,
        "rounds": [_round(r, links) for r in entry.rounds],
    }


def build_event(
    event_id: str,
    df: pd.DataFrame,
    *,
    all_games: pd.DataFrame,
    live_series: list[LiveRatingPoint],
    member_events: list[UscfEvent],
    standings: Standings,
    member_id: str,
) -> dict | None:
    """The Rated Event payload over the filtered, lens-applied Games, or None
    when no Game in the UNFILTERED *all_games* belongs to *event_id* (an
    unknown ID, or an event entered but never played)."""
    played = all_games[all_games["UscfEventId"] == event_id] if not all_games.empty else all_games
    if played.empty:
        return None

    games = df[df["UscfEventId"] == event_id] if not df.empty else df
    event = rated_event_summary(event_id, games, live_series, member_events)
    if not event["name"]:  # USCF's events list lacks it: the Games know its name
        event["name"] = str(played.iloc[0]["UscfEventName"])

    series = sorted(set(games["Event"]) - {""}) if not games.empty else []
    series_unmatched = (
        df[(df["UscfEventId"] == "") & df["Event"].isin(series)].to_dict("records")
        if series else []
    )
    urls_by_round = round_chapter_urls(event["rows"], series_unmatched)

    sections = []
    for name in event["sections"]:
        table = standings.get((event_id, name), [])
        sections.append({
            **section_placement(event_id, name, standings, member_id),
            "crosstable": [_crosstable_row(entry, member_id, urls_by_round)
                           for entry in table],
        })

    performance = performance_by_event(games).get(event_id) if not games.empty else None
    return {
        "games_count": len(games),
        **rated_event_facts(event, performance, rows_by_url(games)),
        "series": series,
        "sections": sections,
    }
