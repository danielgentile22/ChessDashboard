"""
api.routes.analysis
===================
GET /api/v1/analysis: the Analysis screen.

A 501 stub until #115 builds it: read the store (this screen
takes no filters, per the contract), pass it to a ``payloads.analysis`` builder, ``ok()``.
"""
from __future__ import annotations

from api.http import bp, not_implemented


@bp.get("/analysis")
def analysis():
    return not_implemented("Analysis")
