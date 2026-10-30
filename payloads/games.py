"""
payloads.games
==============
The Games screen: every filtered Game as a summary row, in archive order.
Sorting and search are client-side, as on the web table.
"""
from __future__ import annotations

import pandas as pd

from payloads.common import game_summaries


def build_games(df: pd.DataFrame) -> dict:
    """The Games payload over the filtered, lens-applied Games."""
    return {"games_count": len(df), "games": game_summaries(df)}
