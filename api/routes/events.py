"""
api.routes.events
=================
GET /api/v1/events: the Events screen.

A 501 stub until #113 builds it: parse the filters, call
``filtered_games()``, pass the Games to a ``payloads.events`` builder, ``ok()``.
"""
from __future__ import annotations

from api.http import bp, not_implemented


@bp.get("/events")
def events():
    return not_implemented("Events")
