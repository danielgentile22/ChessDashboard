"""
payloads.opponent_ids
=====================
The opaque opponent ID the API hands out (``OpponentId`` in the contract).

Two forms, both derived from the whole (unfiltered) archive so filters never
change an ID:

* ``uscf-<member id>`` when an opponent's matched Games carry exactly one USCF
  member ID and no other Opponent name carries it (strictly unambiguous, as
  in ADR 0007).  It survives a Chapter-header rename.
* ``name-<base64url of the trimmed name, unpadded>`` for everyone else.
  Reversible, so it needs no lookup table and cannot collide.

A ``name-`` ID keeps resolving after the opponent later gains a USCF match,
so a client's saved ID never breaks; responses carry the canonical form.
"""
from __future__ import annotations

import base64
import binascii
from collections import defaultdict

import pandas as pd

_USCF = "uscf-"
_NAME = "name-"


def name_id(name: str) -> str:
    """The ``name-`` form for an Opponent name."""
    raw = base64.urlsafe_b64encode(name.strip().encode()).decode()
    return _NAME + raw.rstrip("=")


def _decode_name(raw: str) -> str | None:
    try:
        return base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)).decode()
    except (binascii.Error, UnicodeDecodeError, ValueError):
        return None


def opponent_ids(df: pd.DataFrame) -> dict[str, str]:
    """Every named opponent in *df* mapped to its canonical ID."""
    if df.empty:
        return {}
    member_ids: dict[str, set[str]] = defaultdict(set)
    for name, member_id in zip(df["Opponent"], df["UscfOpponentId"]):
        name = name.strip() if isinstance(name, str) else ""
        if not name:
            continue
        member_ids[name]  # a name with no match still gets an ID
        if isinstance(member_id, str) and member_id:
            member_ids[name].add(member_id)

    names_per_member: dict[str, int] = defaultdict(int)
    for ids in member_ids.values():
        for member_id in ids:
            names_per_member[member_id] += 1

    def _canonical(name: str, ids: set[str]) -> str:
        if len(ids) == 1:
            (member_id,) = ids
            if names_per_member[member_id] == 1:
                return _USCF + member_id
        return name_id(name)

    return {name: _canonical(name, ids) for name, ids in member_ids.items()}


def resolve_opponent(df: pd.DataFrame, opponent_id: str) -> str | None:
    """The Opponent name an ID refers to in *df*, or None when it names no
    opponent there (unknown, malformed, or ambiguous)."""
    ids = opponent_ids(df)
    if opponent_id.startswith(_NAME):
        name = _decode_name(opponent_id.removeprefix(_NAME))
        return name if name and name in ids else None
    for name, canonical in ids.items():
        if canonical == opponent_id:
            return name
    return None
