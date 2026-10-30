"""
api.routes.game
===============
GET /api/v1/games/{game_id}: the Game detail screen.

A 501 stub until #115 builds it: read the store (this screen
takes no filters, per the contract), pass it to a ``payloads.game`` builder, ``ok()``.
"""
from __future__ import annotations

from api.http import bp, not_implemented


@bp.get("/games/<game_id>")
def game(game_id: str):
    return not_implemented("Game detail")
