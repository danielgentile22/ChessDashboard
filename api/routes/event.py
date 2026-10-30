"""
api.routes.event
================
GET /api/v1/events/{event_id}: the Rated Event screen.

A 501 stub until #113 builds it: parse the filters, call
``filtered_games()``, pass the Games to a ``payloads.event`` builder, ``ok()``.
"""
from __future__ import annotations

from api.http import bp, not_implemented


@bp.get("/events/<event_id>")
def event(event_id: str):
    return not_implemented("Rated Event")
