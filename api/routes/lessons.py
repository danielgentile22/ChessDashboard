"""
api.routes.lessons
==================
GET /api/v1/lessons: the Lessons screen.

A 501 stub until #114 builds it: parse the filters, call
``filtered_games()``, pass the Games to a ``payloads.lessons`` builder, ``ok()``.
"""
from __future__ import annotations

from api.http import bp, not_implemented


@bp.get("/lessons")
def lessons():
    return not_implemented("Lessons")
