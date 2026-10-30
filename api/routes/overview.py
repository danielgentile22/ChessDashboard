"""
api.routes.overview
===================
GET /api/v1/overview: the Overview screen.

A 501 stub until #112 builds it: parse the filters, call
``filtered_games()``, pass the Games to a ``payloads.overview`` builder, ``ok()``.
"""
from __future__ import annotations

from api.http import bp, not_implemented


@bp.get("/overview")
def overview():
    return not_implemented("Overview")
