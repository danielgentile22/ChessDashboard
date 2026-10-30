"""
api.routes.overview
===================
GET /api/v1/overview: the Overview screen.  The USCF card follows Syncs, not
the filters, exactly as on the web.
"""
from __future__ import annotations

from flask import request

import data
from api.http import bp, filtered_games, ok, parse_filters
from api.routes import meta
from payloads.overview import build_overview, uscf_card


@bp.get("/overview")
def overview():
    f = parse_filters(request.args)
    return ok(build_overview(
        filtered_games(f),
        uscf_card=uscf_card(
            enabled=data.uscf_enabled(),
            profile=data.get_uscf_profile(),
            failure=data.uscf_failure(),
            unavailable_since=data.uscf_unavailable_since(),
            live_series=data.get_live_series(),
            today=meta.today(),  # the membership alert's "today", pinned in tests
        ),
        achievements=data.get_uscf_achievements(),
        start=f.start,
        end=f.end,
    ))
