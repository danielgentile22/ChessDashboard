"""
api.http
========
The blueprint every API route registers on, and the only request-handling
helpers routes need: filter parsing, the filtered Games, JSON errors, and the
501 stub for a screen that isn't built yet.

Routes hold no logic beyond parsing, auth, and serialization (ADR 0008):
parse the query string here, call :func:`filtered_games` once (so the lens is
still applied in exactly one place, ``filters.get_filtered``), hand the Games
to a ``payloads`` builder, and return :func:`ok`.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import date

import pandas as pd
from flask import Blueprint, Response, jsonify, request
from werkzeug.datastructures import MultiDict

from uscf_core import LIVE_LENS, OFFICIAL_LENS

bp = Blueprint("api_v1", __name__, url_prefix="/api/v1")

_COLORS = {"White", "Black"}
_OUTCOMES = {"Win", "Draw", "Loss"}
_LENSES = {OFFICIAL_LENS, LIVE_LENS}


class ApiError(Exception):
    """Abort the request with the contract's JSON error body."""

    def __init__(self, code: str, message: str, status: int) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status


def error(code: str, message: str, status: int) -> tuple[Response, int]:
    """The JSON error body every non-2xx response carries."""
    return jsonify(error={"code": code, "message": message}), status


def ok(payload: dict) -> Response:
    """A 200 JSON response."""
    return jsonify(payload)


def not_implemented(screen: str) -> tuple[Response, int]:
    """The 501 a screen route answers until its ticket builds it."""
    return error("not_implemented", f"The {screen} screen isn't served yet.", 501)


@bp.errorhandler(ApiError)
def _api_error(exc: ApiError):
    return error(exc.code, exc.message, exc.status)


@dataclass(frozen=True)
class FilterArgs:
    """The query parameters, one to one with ``filters.FILTER_INPUTS``.

    Empty lists and None mean "no restriction", as on the web.
    """

    colors: list[str]
    outcomes: list[str]
    terminations: list[str]
    start: str | None
    end: str | None
    series: list[str]
    min_moves: int | None
    max_moves: int | None
    lens: str


def _choices(args: MultiDict, name: str, allowed: set[str]) -> list[str]:
    values = args.getlist(name)
    bad = [v for v in values if v not in allowed]
    if bad:
        raise ApiError("bad_request", f"Unknown {name}: {', '.join(bad)}", 400)
    return values


def _iso_date(args: MultiDict, name: str) -> str | None:
    raw = args.get(name)
    if not raw:
        return None
    try:
        return date.fromisoformat(raw).isoformat()
    except ValueError:
        raise ApiError("bad_request", f"{name} must be a YYYY-MM-DD date", 400) from None


def _count(args: MultiDict, name: str) -> int | None:
    raw = args.get(name)
    if raw is None or raw == "":
        return None
    if not raw.isdigit():
        raise ApiError("bad_request", f"{name} must be a whole number", 400)
    return int(raw)


def parse_filters(args: MultiDict) -> FilterArgs:
    """The filter state a request's query string asks for."""
    lens = args.get("lens") or OFFICIAL_LENS
    if lens not in _LENSES:
        raise ApiError("bad_request", "lens must be official or live", 400)
    return FilterArgs(
        colors=_choices(args, "colors", _COLORS),
        outcomes=_choices(args, "outcomes", _OUTCOMES),
        terminations=args.getlist("terminations"),
        start=_iso_date(args, "start"),
        end=_iso_date(args, "end"),
        series=args.getlist("series"),
        min_moves=_count(args, "min_moves"),
        max_moves=_count(args, "max_moves"),
        lens=lens,
    )


def filtered_games(f: FilterArgs | None = None) -> pd.DataFrame:
    """The Games this request's filters and lens select, through the one
    shared helper every Dash page uses."""
    from filters import get_filtered  # imports Dash; keep it off module import

    f = f or parse_filters(request.args)
    moves = None
    if f.min_moves is not None or f.max_moves is not None:
        moves = [f.min_moves if f.min_moves is not None else 0,
                 f.max_moves if f.max_moves is not None else 10**6]
    return get_filtered(f.colors, f.outcomes, f.terminations, f.start, f.end,
                        f.series, moves, f.lens)
