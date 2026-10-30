"""
api.routes.opponents
====================
GET /api/v1/opponents: the Opponents screen.

A 501 stub until #114 builds it: parse the filters, call
``filtered_games()``, pass the Games to a ``payloads.opponents`` builder, ``ok()``.
"""
from __future__ import annotations

from api.http import bp, not_implemented


@bp.get("/opponents")
def opponents():
    return not_implemented("Opponents")
