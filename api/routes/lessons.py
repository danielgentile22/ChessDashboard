"""
api.routes.lessons
==================
GET /api/v1/lessons: the Lessons screen.

The global filters select the list's Games; ``tags`` and ``opponent`` narrow
only the list.  The review queue, the picker, and the Coach's Notes read the
whole archive under the same lens.
"""
from __future__ import annotations

from dataclasses import replace

from flask import request

import data
from api.http import ApiError, bp, filtered_games, ok, parse_filters
from payloads.lessons import build_lessons

_BOOLEANS = {"true": True, "1": True, "false": False, "0": False}


@bp.get("/lessons")
def lessons():
    f = parse_filters(request.args)
    review = _BOOLEANS.get(request.args.get("review", "false").lower())
    if review is None:
        raise ApiError("bad_request", "review must be true or false", 400)
    everything = replace(f, colors=[], outcomes=[], terminations=[], start=None, end=None,
                         series=[], min_moves=None, max_moves=None)
    return ok(build_lessons(
        filtered_games(f),
        filtered_games(everything),
        tags=[t for t in request.args.getlist("tags") if t],
        opponent_id=request.args.get("opponent") or None,
        review=review,
        coach_notes=data.get_coach_notes(),
    ))
