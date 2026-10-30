"""
api
===
The versioned JSON API for the native iOS client (ADR 0008).

A thin Flask blueprint on the same server and the same single worker as Dash.
It is a read surface over the per-user store, like a page: routes parse the
query string, call ``filters.get_filtered`` once, hand the Games to a pure
``payloads`` builder, and serialize.  It never fetches, never mutates the
store, and never computes stats inline.  Auth is the existing gate
(``auth``), which accepts a session cookie or a bearer token.

Layout: ``api.http`` holds the blueprint and the request helpers; each route
lives in its own ``api/routes/<screen>.py``, imported below so it registers.
The contract is ``openapi/v1.json`` (see ``api.contract``).
"""
from __future__ import annotations

from flask import Flask

from api.http import bp
from api.routes import (  # noqa: F401  (importing a route module registers it)
    analysis,
    event,
    events,
    game,
    games,
    lessons,
    meta,
    openings,
    opponent,
    opponents,
    overview,
    session,
    sync,
    trends,
)


@bp.route("/<path:_unknown>", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
def _no_such_route(_unknown: str):
    from api.http import error

    return error("not_found", "No such API route.", 404)


def install(server: Flask) -> None:
    """Serve the API from *server* under ``/api/v1``."""
    server.register_blueprint(bp)
