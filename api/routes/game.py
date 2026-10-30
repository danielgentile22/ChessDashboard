"""
api.routes.game
===============
GET /api/v1/games/{game_id}: the Game detail screen.

Takes no filters, per the contract: like the web page, it looks the Game up
in the full, unfiltered store.
"""
from __future__ import annotations

import data
from api.http import ApiError, bp, ok
from payloads.common import game_id as game_id_of
from payloads.game import build_game


@bp.get("/games/<game_id>")
def game(game_id: str):
    df = data.get_df()
    matches = df[df["ChapterURL"].map(game_id_of) == game_id] if not df.empty else df
    if matches.empty:
        raise ApiError("not_found", f"No Game {game_id!r} in this archive.", 404)
    row = matches.to_dict("records")[0]
    coach = data.get_coach_chapter(row["ChapterURL"])
    return ok(build_game(row, player=data.get_player(),
                         coach_movetext=coach.movetext if coach is not None else None))
