"""
api.routes.opponent
===================
GET /api/v1/opponents/{opponent_id}: the Scouting Report screen.

A 501 stub until #114 builds it: parse the filters, call
``filtered_games()``, pass the Games to a ``payloads.opponent`` builder, ``ok()``.
"""
from __future__ import annotations

from api.http import bp, not_implemented


@bp.get("/opponents/<opponent_id>")
def opponent(opponent_id: str):
    return not_implemented("Scouting Report")
