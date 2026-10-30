"""
api.routes.openings
===================
GET /api/v1/openings: the Openings screen.
"""
from __future__ import annotations

from api.http import bp, filtered_games, ok
from payloads.openings import build_openings


@bp.get("/openings")
def openings():
    return ok(build_openings(filtered_games()))
