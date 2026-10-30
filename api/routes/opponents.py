"""
api.routes.opponents
====================
GET /api/v1/opponents: the Opponents screen.
"""
from __future__ import annotations

import data
from api.http import bp, filtered_games, ok
from payloads.opponents import build_opponents


@bp.get("/opponents")
def opponents():
    return ok(build_opponents(filtered_games(), data.get_df()))
