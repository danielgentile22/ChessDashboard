"""
api.routes.sync
===============
POST /api/v1/sync: run a Sync and report what the web toast reports.

Owner only: a guest gets 403 before anything runs, exactly like the web Sync
button's server-side check.  Demo mode may not write either (403); a failed
Sync is a 502 and the current data stays.
"""
from __future__ import annotations

import auth
import data
from api.http import bp, error, ok
from payloads.sync import build_sync


@bp.post("/sync")
def sync():
    if not auth.can_write():
        return error("forbidden", "Guests can't Sync. Sign in as the owner.", 403)
    # refresh() swaps the store, so this keeps the milestone baseline.
    before = data.get_df()
    outcome = data.refresh()
    if outcome.status == "demo":
        return error("forbidden", outcome.error, 403)
    if outcome.status == "error":
        return error("sync_failed", outcome.error, 502)
    return ok(build_sync(
        status=outcome.status,
        new_games=outcome.new_games,
        failures=outcome.failures,
        before=before,
        after=data.get_df(),
        new_achievements=data.get_new_achievements(),
        synced_at=data.synced_at(),
        uscf_synced_at=data.uscf_synced_at(),
        uscf_unavailable_since=data.uscf_unavailable_since(),
    ))
