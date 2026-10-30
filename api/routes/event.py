"""
api.routes.event
================
GET /api/v1/events/{event_id}: the Rated Event screen.
"""
from __future__ import annotations

import data
from api.http import ApiError, bp, filtered_games, ok
from payloads.event import build_event


@bp.get("/events/<event_id>")
def event(event_id: str):
    profile = data.get_uscf_profile()
    payload = build_event(
        event_id,
        filtered_games(),
        all_games=data.get_df(),
        live_series=data.get_live_series(),
        member_events=data.get_uscf_events(),
        standings=data.get_uscf_standings(),
        member_id=profile.member_id if profile else "",
    )
    if payload is None:
        raise ApiError("not_found", f"No Game belongs to Rated Event {event_id}.", 404)
    return ok(payload)
