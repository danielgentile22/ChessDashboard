"""
api.routes.games
================
GET /api/v1/games: the Games screen.
"""
from __future__ import annotations

from api.http import bp, filtered_games, ok
from payloads.games import build_games


@bp.get("/games")
def games():
    return ok(build_games(filtered_games()))
