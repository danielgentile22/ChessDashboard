"""
tests/test_api_lessons.py
=========================
GET /api/v1/lessons: the response validates against openapi/v1.json and is
recorded as openapi/fixtures/getLessons.json for the iOS tests.
"""
from __future__ import annotations

from payloads.opponent_ids import name_id

CHAP1 = "https://lichess.org/study/teststudy/chap0001"


def test_lessons_matches_the_contract(api):
    body = api.get("/api/v1/lessons", record="getLessons")
    assert body["games_count"] > 0
    assert body["review"] is None


def test_lessons_are_newest_first_with_their_game(api):
    lessons = api.get("/api/v1/lessons")["lessons"]
    assert len(lessons) == 3
    dates = [lesson["game"]["date"] for lesson in lessons]
    assert dates == sorted(dates, reverse=True)
    assert lessons[0]["text"] and not lessons[0]["text"].startswith("Lesson:")


def test_tag_counts_carry_the_source_split(api):
    counts = api.get("/api/v1/lessons")["tag_counts"]
    assert [c["name"] for c in counts if c["canonical"]] == [
        "opening", "tactics", "endgame", "blunder", "strategy"]
    assert all(c["count"] == c["mine_count"] + c["engine_count"] for c in counts)


def test_tags_and_opponent_narrow_only_the_list(api):
    full = api.get("/api/v1/lessons")
    body = api.get("/api/v1/lessons", query_string={"tags": "opening"})
    assert len(body["lessons"]) == 2
    assert body["tag_counts"] == full["tag_counts"]
    body = api.get("/api/v1/lessons", query_string={"opponent": "uscf-10000001"})
    assert len(body["lessons"]) == 3
    assert api.get("/api/v1/lessons", query_string={"opponent": "uscf-1"})["lessons"] == []


def test_the_lessons_opponent_picker(api):
    picker = api.get("/api/v1/lessons")["lessons_opponents"]
    assert picker == [{"opponent_id": "uscf-10000001", "opponent": "Opponent A"}]


def test_review_mode_is_primed_and_ignores_filters(api):
    body = api.get("/api/v1/lessons", record="getLessons.review",
                   query_string={"review": "true", "opponent": "uscf-10000001",
                                 "outcomes": "Loss"})
    assert body["lessons"] == []
    review = body["review"]
    assert review["opponent_id"] == "uscf-10000001" and review["opponent"] == "Opponent A"
    assert len(review["cards"]) == 3
    assert {c["reason_kind"] for c in review["cards"]} == {"facing_opponent"}
    assert review["cards"][0]["reason"] == "You're facing Opponent A"


def test_review_with_an_unknown_opponent_is_unprimed(api):
    review = api.get("/api/v1/lessons", query_string={
        "review": "1", "opponent": name_id("Nobody")})["review"]
    assert review["opponent_id"] is None and review["opponent"] is None
    assert {c["reason_kind"] for c in review["cards"]} == {"recent"}


def test_a_non_boolean_review_is_a_400(api):
    api.get("/api/v1/lessons", query_string={"review": "maybe"}, status=400)


def test_coach_notes_are_unfiltered_with_their_game(api, monkeypatch):
    import data

    monkeypatch.setattr(data, "get_coach_notes", lambda: [{
        "text": "Develop the knight before the bishop.", "move_number": 3,
        "chapter_url": CHAP1, "chapter_id": "chap0001", "opponent": "Opponent A",
        "outcome": "Win", "date": "", "date_dt": None,
    }])
    body = api.get("/api/v1/lessons", record="getLessons.coach_notes",
                   query_string={"outcomes": "Loss"})
    assert [(n["text"], n["move_number"], n["game"]["chapter_url"])
            for n in body["coach_notes"]] == [
        ("Develop the knight before the bishop.", 3, CHAP1)]


def test_recurring_weaknesses_and_their_review_cards(api, monkeypatch):
    import data

    # Three recent losses sharing #time-trouble: a real recurring weakness
    df = data.get_df().copy()
    for i in (0, 2, 4):
        df.at[i, "Outcome"] = "Loss"
        df.at[i, "Tags"] = [*df.at[i, "Tags"], "time-trouble"]
    monkeypatch.setattr(data, "get_df", lambda: df)

    body = api.get("/api/v1/lessons", record="getLessons.weakness",
                   query_string={"review": "true"})
    (weakness,) = body["recurring_weaknesses"]
    assert weakness["tag"] == "time-trouble" and weakness["loss_count"] == 3
    assert [g["game_id"] for g in weakness["games"]] == ["chap0001", "chap0003", "chap0005"]
    assert body["review"]["cards"][0]["reason_kind"] == "recurring_weakness"
    assert body["review"]["cards"][0]["reason"] == "Recurring weakness: #time-trouble"


def test_uscf_off_still_validates(api_lichess_only):
    body = api_lichess_only.get("/api/v1/lessons")
    assert body["lessons_opponents"] == [
        {"opponent_id": name_id("Opponent A"), "opponent": "Opponent A"}]
