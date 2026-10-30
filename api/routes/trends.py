"""
api.routes.trends
=================
GET /api/v1/trends: the Trends screen.

A 501 stub until #112 builds it: parse the filters, call
``filtered_games()``, pass the Games to a ``payloads.trends`` builder, ``ok()``.
"""
from __future__ import annotations

from api.http import bp, not_implemented


@bp.get("/trends")
def trends():
    return not_implemented("Trends")
