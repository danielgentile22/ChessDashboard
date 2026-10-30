"""
tests/test_payloads_opponents.py
================================
The opaque opponent ID (``payloads.opponent_ids``) and the Opponents,
Scouting Report, and Lessons builders' pure rules.
"""
from __future__ import annotations

import base64
from types import SimpleNamespace

import pandas as pd
import pytest

from payloads.lessons import lesson_tag_counts
from payloads.opponent import uscf_identity
from payloads.opponent_ids import name_id, opponent_ids, resolve_opponent


def _games(*rows: tuple[str, str]) -> pd.DataFrame:
    """Minimal Games: (Opponent, UscfOpponentId) pairs."""
    return pd.DataFrame([{"Opponent": o, "UscfOpponentId": u} for o, u in rows])


class TestOpponentIds:
    def test_a_strictly_unambiguous_uscf_match_gets_the_member_id_form(self):
        ids = opponent_ids(_games(("Ann", "111"), ("Ann", ""), ("Bob", "")))
        assert ids["Ann"] == "uscf-111"
        assert ids["Bob"] == name_id("Bob")

    def test_two_member_ids_on_one_name_fall_back_to_the_name_form(self):
        ids = opponent_ids(_games(("Ann", "111"), ("Ann", "222")))
        assert ids["Ann"] == name_id("Ann")

    def test_one_member_id_on_two_names_falls_back_for_both(self):
        ids = opponent_ids(_games(("Ann", "111"), ("Annie", "111")))
        assert ids == {"Ann": name_id("Ann"), "Annie": name_id("Annie")}

    def test_an_empty_archive_has_no_ids(self):
        assert opponent_ids(pd.DataFrame()) == {}

    def test_blank_opponents_have_no_id(self):
        assert opponent_ids(_games(("", ""), ("  ", "111"))) == {}

    def test_the_name_form_is_url_safe_unpadded_base64(self):
        nid = name_id("Zoë Ölund")
        assert nid.startswith("name-") and "=" not in nid
        raw = nid.removeprefix("name-")
        assert base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)).decode() == "Zoë Ölund"

    def test_resolves_both_forms_and_an_old_name_id_after_a_uscf_match(self):
        df = _games(("Ann", "111"), ("Bob", ""))
        assert resolve_opponent(df, "uscf-111") == "Ann"
        assert resolve_opponent(df, name_id("Bob")) == "Bob"
        assert resolve_opponent(df, name_id("Ann")) == "Ann"  # saved before the match

    @pytest.mark.parametrize("bad", ["uscf-999", "name-!!!", "name-", "name-a", "name-_w", "Ann", name_id("Nobody")])
    def test_unknown_or_malformed_ids_resolve_to_none(self, bad):
        assert resolve_opponent(_games(("Ann", "111")), bad) is None


class TestUscfIdentity:
    def _games(self, then: float | None) -> pd.DataFrame:
        return pd.DataFrame([
            {"UscfOpponentId": "", "UscfOpponentName": "", "OpponentRatingNum": None},
            {"UscfOpponentId": "111", "UscfOpponentName": "ANN SMITH", "OpponentRatingNum": then},
        ])

    def _profiles(self, now: int | None) -> dict:
        rating = SimpleNamespace(rating=now) if now is not None else None
        return {"111": SimpleNamespace(rating=lambda kind: rating if kind == "R" else None)}

    def test_then_vs_now(self):
        identity = uscf_identity(self._games(1500), "Ann", 1500, self._profiles(1580))
        assert identity == {
            "member_id": "111",
            "name": "ANN SMITH",
            "profile_url": identity["profile_url"],
            "rating_when_last_played": 1500,
            "official_rating": 1580,
            "rating_change": 80,
        }
        assert "111" in identity["profile_url"]

    def test_no_profile_leaves_now_and_the_change_null(self):
        identity = uscf_identity(self._games(1500), "Ann", 1500, {})
        assert identity["official_rating"] is None and identity["rating_change"] is None

    def test_none_without_a_matched_game(self):
        games = self._games(1500).iloc[:1]
        assert uscf_identity(games, "Ann", 1500, self._profiles(1580)) is None


class TestLessonTagCounts:
    def test_splits_each_count_by_source(self):
        df = pd.DataFrame({
            "Tags": [["tactics", "blunder"], ["tactics"], ["queen-trap"]],
            "TagSources": [{"tactics": "engine", "blunder": "mine"},
                           {"tactics": "mine"}, {}],
        })
        assert lesson_tag_counts(df) == [
            {"name": "tactics", "canonical": True, "count": 2, "mine_count": 1, "engine_count": 1},
            {"name": "blunder", "canonical": True, "count": 1, "mine_count": 1, "engine_count": 0},
            {"name": "queen-trap", "canonical": False, "count": 1, "mine_count": 1, "engine_count": 0},
        ]
