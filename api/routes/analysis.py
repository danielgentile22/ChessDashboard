"""
api.routes.analysis
===================
GET /api/v1/analysis: the Analysis screen.

Takes no filters, per the contract: like the web page, it reads the full,
unfiltered store.
"""
from __future__ import annotations

import data
from api.http import bp, ok
from payloads.analysis import build_analysis


@bp.get("/analysis")
def analysis():
    return ok(build_analysis(data.get_df()))
