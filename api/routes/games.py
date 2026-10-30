"""
api.routes.games
================
GET /api/v1/games: the Games screen.

A 501 stub until #113 builds it: parse the filters, call
``filtered_games()``, pass the Games to a ``payloads.games`` builder, ``ok()``.
"""
from __future__ import annotations

from api.http import bp, not_implemented


@bp.get("/games")
def games():
    return not_implemented("Games")
