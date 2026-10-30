"""
api.routes.opponent
===================
GET /api/v1/opponents/{opponent_id}: the Scouting Report screen.

The ID resolves against the whole archive: one that names no opponent there
is a 404; one whose Games all fall outside the filters is an empty report.
"""
from __future__ import annotations

import data
from api.http import ApiError, bp, filtered_games, ok
from payloads.opponent import build_opponent
from payloads.opponent_ids import opponent_ids, resolve_opponent


@bp.get("/opponents/<opponent_id>")
def opponent(opponent_id: str):
    archive = data.get_df()
    name = resolve_opponent(archive, opponent_id)
    if name is None:
        raise ApiError("not_found", "No opponent has that ID.", 404)
    return ok(build_opponent(filtered_games(), name, opponent_ids(archive)[name],
                             data.get_opponent_profiles()))
