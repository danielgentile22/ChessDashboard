"""
payloads.events
===============
The Events screen: each Series and the Rated Events inside it, the
Performance per Series chart, and the Rated Events entered but never played.

Also the pieces the web Rated Event card and the Rated Event payload share
(``payloads.event``): performance per Rated Event, the player's crosstable
row, and which Game each real round links to.  The Forfeit rule holds
throughout: a Forfeit win counts toward score but never as a game, a win, or
a Streak (``uscf_core.series_summary``).
"""
from __future__ import annotations

from collections.abc import Iterable, Mapping

import pandas as pd

from payloads.common import game_summary, iso_date, optional_int, whole_rating
from pgn_stats_core import event_summary, performance_rating_stats
from uscf_core import LiveRatingPoint, StandingEntry, UscfEvent, series_summary, unplayed_events

# The Performance per Series chart shows this many Series.
SERIES_CHART_LIMIT = 20

Standings = Mapping[tuple[str, str], list[StandingEntry]]


def performance_by_event(df: pd.DataFrame) -> dict[str, int | None]:
    """Performance rating per Rated Event over *df*'s Games (Forfeits and
    unrated opponents excluded); None where none qualify."""
    return {
        str(event_id): performance_rating_stats(games)["performance_rating"]
        for event_id, games in df[df["UscfEventId"] != ""].groupby("UscfEventId")
    }


def player_entry(standings: list[StandingEntry], member_id: str) -> StandingEntry | None:
    """The player's own row in a Section's crosstable, if it is there."""
    return next((s for s in standings if member_id and s.member_id == member_id), None)


def round_chapter_urls(event_rows: Iterable[Mapping],
                       series_unmatched_rows: Iterable[Mapping]) -> dict[int, str]:
    """Real round (UscfRound) -> ChapterURL, for the player's crosstable round
    links.  The Series' unmatched Forfeits ride along (their crosstable round
    was attached through this very event's crosstable), but never its other
    unmatched Games, which could collide on round numbers."""
    forfeits = [row for row in series_unmatched_rows if row.get("Forfeit")]
    return {
        int(row["UscfRound"]): row["ChapterURL"]
        for row in [*event_rows, *forfeits]
        if pd.notna(row.get("UscfRound")) and row.get("ChapterURL")
    }


def rating_change(pre: float | None, post: float | None) -> int | None:
    """round(post) - round(pre), or None when either is unknown."""
    pre_whole, post_whole = whole_rating(pre), whole_rating(post)
    if pre_whole is None or post_whole is None:
        return None
    return post_whole - pre_whole


def rows_by_url(df: pd.DataFrame) -> dict[str, dict]:
    """Every Game in *df* keyed by ChapterURL, for turning the cores' trimmed
    Game rows back into full summary rows."""
    return {row["ChapterURL"]: row for row in df.to_dict("records")} if not df.empty else {}


def game_row(row: Mapping, full_rows: Mapping[str, Mapping]) -> dict:
    """One Game line of a Rated Event or the unmatched block.  The round is
    the REAL one from the crosstable when known, else the typed Round."""
    real_round = row.get("UscfRound")
    has_real = real_round is not None and pd.notna(real_round)
    return {
        "round": optional_int(real_round if has_real else row.get("RoundNum")),
        "forfeit": bool(row.get("Forfeit")),
        "game": game_summary(full_rows[row["ChapterURL"]]),
    }


def section_placement(event_id: str, section: str, standings: Standings,
                      member_id: str) -> dict:
    """One Section played, with the player's final placement when its
    crosstable is cached."""
    table = standings.get((event_id, section))
    if table is None:
        return {"name": section, "has_crosstable": False,
                "placement": None, "player_count": None}
    me = player_entry(table, member_id)
    return {"name": section, "has_crosstable": True,
            "placement": me.ordinal if me else None, "player_count": len(table)}


def rated_event_facts(event: Mapping, performance: int | None,
                      full_rows: Mapping[str, Mapping]) -> dict:
    """The Rated Event fields the Events card and the Rated Event screen
    share, from one ``uscf_core`` Rated Event entry."""
    return {
        "event_id": event["event_id"],
        "name": event["name"],
        "start": event["start"],
        "end": event["end"],
        "player_count": event["player_count"],
        "game_count": event["games"],
        "forfeit_count": event["forfeits"],
        "win": event["win"],
        "draw": event["draw"],
        "loss": event["loss"],
        "score": event["score"],
        "pre_rating": whole_rating(event["pre"]),
        "post_rating": whole_rating(event["post"]),
        "rating_change": rating_change(event["pre"], event["post"]),
        "performance_rating": whole_rating(performance),
        "games": [game_row(row, full_rows) for row in event["rows"]],
    }


def _series_bars(df: pd.DataFrame) -> list[dict]:
    bars = event_summary(df).tail(SERIES_CHART_LIMIT)
    return [{
        "series": row["Event"],
        "first_date": row["FirstDate"] or None,
        "win": int(row["Win"]),
        "draw": int(row["Draw"]),
        "loss": int(row["Loss"]),
    } for row in bars.to_dict("records")]


def _unplayed(event: UscfEvent) -> dict:
    return {
        "event_id": event.event_id,
        "name": event.name,
        "start": iso_date(event.start_date),
        "end": iso_date(event.end_date),
        "player_count": event.player_count,
    }


def build_events(
    df: pd.DataFrame,
    *,
    all_games: pd.DataFrame,
    live_series: list[LiveRatingPoint],
    member_events: list[UscfEvent],
    standings: Standings,
    member_id: str,
    start: str | None,
    end: str | None,
) -> dict:
    """The Events payload over the filtered, lens-applied Games.

    *all_games* is the UNFILTERED store: whether a Rated Event was ever
    played can't depend on the filters; only *start*/*end* bound which
    unplayed events are listed.
    """
    full_rows = rows_by_url(df)
    performance = performance_by_event(df) if not df.empty else {}
    series = []
    for group in series_summary(df, live_series, member_events):
        series.append({
            "series": group["series"],
            "first_date": group["first_date"] or None,
            "game_count": group["games"],
            "forfeit_count": group["forfeits"],
            "win": group["win"],
            "draw": group["draw"],
            "loss": group["loss"],
            "score": group["score"],
            "longest_win_streak": group["win_streak"],
            "rated_events": [{
                **rated_event_facts(event, performance.get(event["event_id"]), full_rows),
                "sections": [section_placement(event["event_id"], name, standings, member_id)
                             for name in event["sections"]],
            } for event in group["rated_events"]],
            "unmatched_games": [game_row(row, full_rows) for row in group["unmatched"]],
        })
    return {
        "games_count": len(df),
        "series_performance": _series_bars(df),
        "series": series,
        "unplayed_events": [_unplayed(e) for e in unplayed_events(
            all_games, member_events, date_start=start, date_end=end)],
    }
