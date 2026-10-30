"""
api.routes.events
=================
GET /api/v1/events: the Events screen.
"""
from __future__ import annotations

from flask import request

import data
from api.http import bp, filtered_games, ok, parse_filters
from payloads.events import build_events


@bp.get("/events")
def events():
    f = parse_filters(request.args)
    profile = data.get_uscf_profile()
    return ok(build_events(
        filtered_games(f),
        all_games=data.get_df(),
        live_series=data.get_live_series(),
        member_events=data.get_uscf_events(),
        standings=data.get_uscf_standings(),
        member_id=profile.member_id if profile else "",
        start=f.start,
        end=f.end,
    ))
