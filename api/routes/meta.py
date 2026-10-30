"""
api.routes.meta
===============
GET /api/v1/meta: who is signed in, the filter options and presets, and how
fresh each source is.  Unfiltered by design.
"""
from __future__ import annotations

from datetime import date

import auth
import data
from api.http import bp, ok
from payloads.meta import build_meta


def today() -> date:
    """Today, for the "This year" preset (a seam the contract tests pin)."""
    return date.today()


@bp.get("/meta")
def meta():
    return ok(build_meta(
        data.get_df(),
        player=data.get_player(),
        session={
            "role": auth.current_role() or auth.OWNER,  # ungated: everyone owns it
            "username": auth.current_user(),
            "can_write": auth.can_write() and not data.demo_mode(),
        },
        today=today(),
        demo_mode=data.demo_mode(),
        lichess_synced_at=data.synced_at(),
        lichess_source=data.source(),
        lichess_cached_at=data.cached_at(),
        uscf_enabled=data.uscf_enabled(),
        uscf_available=data.get_uscf_profile() is not None,
        uscf_synced_at=data.uscf_synced_at(),
        uscf_unavailable_since=data.uscf_unavailable_since(),
        new_achievements=data.get_new_achievements(),
    ))
