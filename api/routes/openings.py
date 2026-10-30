"""
api.routes.openings
===================
GET /api/v1/openings: the Openings screen.

A 501 stub until #113 builds it: parse the filters, call
``filtered_games()``, pass the Games to a ``payloads.openings`` builder, ``ok()``.
"""
from __future__ import annotations

from api.http import bp, not_implemented


@bp.get("/openings")
def openings():
    return not_implemented("Openings")
