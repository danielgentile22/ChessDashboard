"""
tests/api_career.py
===================
A data store rich enough to record every Game detail view: the real 63-chapter
Study snapshot (Lichess Studies + the real USCF record), with the Alice
Anderson chapter swapped for its engine-analyzed export, plus the coach Study
whose review chapters match Alice, Diana, and Ethan by their moves.

Coach content needs a user record (``coach_study_ids``), so the store is a
registered user's, activated on this thread the way the gated app's
per-request hook does.  The ungated ``ui_app`` installs no hook, so the
activation holds for every request the test client makes.
"""
from __future__ import annotations

import json
import re
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from unittest import mock

import data
import sync
from tests.conftest import (
    REAL_USCF_EVENTS,
    REAL_USCF_SECTIONS,
    REAL_USCF_SUPPLEMENTS,
    USCF_DATA_DIR,
    stub_ui_sources,
)
from user_config import UserRecord, hash_password

DATA_DIR = Path(__file__).parent / "data"
SNAPSHOT_PGN = (USCF_DATA_DIR / "lichess-study-snapshot.pgn").read_text()
ALICE_PGN = (DATA_DIR / "analyzed-alice-anderson.pgn").read_text()
COACH_PGN = (DATA_DIR / "coach-study.pgn").read_text()

ANALYZED_ID = "alic0001"     # engine-analyzed, coach-reviewed
COACH_ID = "dian0001"        # coach-reviewed, not analyzed
MY_ANALYSIS_ID = "chp00008"  # the player's own variations, not analyzed
UNANALYZED_ID = "fion0001"   # awaiting analysis, no coach review


def _with_analyzed_alice(snapshot: str) -> str:
    """The snapshot with Alice's chapter replaced by its analyzed export."""
    chapters = re.split(r"\n\n(?=\[Event )", snapshot.strip())
    swapped = [ALICE_PGN.strip() if f"/{ANALYZED_ID}\"]" in c else c for c in chapters]
    assert swapped != chapters, "Alice's chapter is missing from the snapshot"
    return "\n\n".join(swapped) + "\n"


@contextmanager
def career_store(tmp_path: Path) -> Iterator[None]:
    """Activate the rich store for the duration of the block."""
    studies = {"s-main": _with_analyzed_alice(SNAPSHOT_PGN), "s-coach": COACH_PGN}
    record = UserRecord(
        username="daniel", password_hash=hash_password("pw"),
        study_ids=("s-main",), coach_study_ids=("s-coach",),
        uscf_member_id="12345678", lichess_token=None,
    )
    games = json.loads((USCF_DATA_DIR / "games.json").read_text())["items"]
    data.reset()
    with stub_ui_sources("", uscf_games=games,
                         uscf_supplements=REAL_USCF_SUPPLEMENTS,
                         uscf_sections=REAL_USCF_SECTIONS,
                         uscf_events=REAL_USCF_EVENTS), \
         mock.patch.object(sync, "fetch_study_pgn",
                           side_effect=lambda study_id, **_: studies[study_id]):
        data.register_users({"daniel": record}, data_dir=str(tmp_path))
        data.sync_user("daniel")
    data.activate("daniel")
    try:
        yield
    finally:
        data.reset()
