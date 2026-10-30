"""
api.routes.trends
=================
GET /api/v1/trends: the Trends screen.  The rating chart takes the store's
full USCF series; only the date range trims them and the lens only picks
which line is emphasized, exactly as on the web.
"""
from __future__ import annotations

from flask import request

import data
from api.http import bp, filtered_games, ok, parse_filters
from payloads.trends import build_trends


@bp.get("/trends")
def trends():
    f = parse_filters(request.args)
    return ok(build_trends(
        filtered_games(f),
        official_series=data.get_official_series(),
        live_series=data.get_live_series(),
        lens=f.lens,
        start=f.start,
        end=f.end,
    ))
