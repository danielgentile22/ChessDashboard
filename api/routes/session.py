"""
api.routes.session
==================
POST /api/v1/session: sign in with the web login's credentials, get a bearer
token.  All checking (credentials, throttle, role) is ``auth.token_sign_in``.
"""
from __future__ import annotations

from flask import request

import auth
from api.http import bp, error, ok
from payloads.common import iso_timestamp


@bp.post("/session")
def session():
    body = request.get_json(silent=True)
    if not isinstance(body, dict):
        return error("bad_request", "Send a JSON object of credentials.", 400)
    username, password, guest = (body.get("username", ""), body.get("password", ""),
                                 body.get("guest", False))
    if not (isinstance(username, str) and isinstance(password, str)
            and isinstance(guest, bool)):
        return error("bad_request", "username and password are strings; guest is a boolean.",
                     400)
    try:
        grant = auth.token_sign_in(username, password, guest=guest)
    except auth.SignInError as exc:
        return error(exc.code, exc.message, exc.status)
    return ok({
        "token": grant.token,
        "role": grant.role,
        "username": grant.username,
        "can_write": grant.can_write,
        "expires_at": iso_timestamp(grant.expires_at),
    })
