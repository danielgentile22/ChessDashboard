"""
payloads.opponents
==================
The Opponents screen: the Scouting Report picker (the whole archive), the
W/D/L record against repeat opponents, W/D/L by rating-difference bucket, and
outcome vs opponent rating.  The same stats the web charts draw.
"""
from __future__ import annotations

import pandas as pd

from payloads.common import iso_date, whole_rating
from payloads.opponent_ids import opponent_ids
from pgn_stats_core import (
    opponent_rating_bucket_summary,
    opponent_summary,
    outcome_vs_rating_data,
)

TOP_RECORDS = 25  # the web chart's cap


def _wdl(row: dict) -> dict:
    return {"games": int(row["Games"]), "win": int(row["Win"]),
            "draw": int(row["Draw"]), "loss": int(row["Loss"])}


def build_opponents(df: pd.DataFrame, archive: pd.DataFrame) -> dict:
    """The Opponents payload over the filtered Games *df*; IDs and the picker
    come from the unfiltered *archive*."""
    ids = opponent_ids(archive)
    records = opponent_summary(df).head(TOP_RECORDS).to_dict("records")
    buckets = opponent_rating_bucket_summary(df).to_dict("records")
    scatter = outcome_vs_rating_data(df)
    return {
        "games_count": len(df),
        "opponents": [{"opponent_id": ids[name], "opponent": name} for name in sorted(ids)],
        "records": [{"opponent_id": ids.get(r["Opponent"]), "opponent": r["Opponent"], **_wdl(r)}
                    for r in records],
        "rating_buckets": [{"bucket": b["Bucket"], **_wdl(b)} for b in buckets],
        "outcome_vs_rating": [{
            "opponent_rating": whole_rating(p["OpponentRatingNum"]),
            "outcome": p["Outcome"],
            "outcome_value": p["OutcomeNum"],
            "opponent": p["Opponent"],
            # The scatter keeps df's index, so its full date is one lookup away
            "date": iso_date(df.at[idx, "Date_dt"]),
        } for idx, p in scatter.iterrows()],
    }
