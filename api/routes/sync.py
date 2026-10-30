"""
api.routes.sync
===============
POST /api/v1/sync: run a Sync and report what the web toast reports.

Owner only: a guest gets 403 before anything runs, exactly like the web Sync
button's server-side check.  The Sync itself is a 501 stub until #115 builds
it over ``data.refresh()``.
"""
from __future__ import annotations

import auth
from api.http import bp, error, not_implemented


@bp.post("/sync")
def sync():
    if not auth.can_write():
        return error("forbidden", "Guests can't Sync. Sign in as the owner.", 403)
    return not_implemented("Sync")
