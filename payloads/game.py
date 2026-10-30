"""
payloads.game
=============
The Game detail screen: one Game in full.

Also the single home of the board PGNs.  The web Game detail page builds its
pgn-viewer mounts from :func:`board_pgns`, so the native board reads exactly
the PGNs the web board plays.

Pure: the caller passes the Game's row, the player's name, and the matched
coach Chapter's movetext (``data.get_coach_chapter``); no Dash, no Flask.
"""
from __future__ import annotations

from collections.abc import Mapping

import pandas as pd

from engine_analysis_core import GameAnalysis, win_pct_from_cp
from payloads.common import game_summary, iso_date, optional_int, tags, whole_rating
from pgn_stats_core import has_my_analysis, mainline_movetext
from uscf_core import USCF_RATING_SYSTEM_LABELS, uscf_member_url

# One store row: a record dict (the API) or a Series (the web page).
GameRow = Mapping | pd.Series


def game_pgn(game: GameRow, movetext: str, player: str) -> str:
    """
    A self-contained PGN (headers + movetext) for one board view.

    The headers give a board the players, result, and date; *movetext*
    supplies the moves (clean for the Game view, annotated for the others).
    """
    color = str(game.get("Color") or "")
    opponent = str(game.get("Opponent") or "?")
    white = player if color == "White" else opponent
    black = opponent if color == "White" else player
    headers = [
        ("Event", game.get("Event")),
        ("Date", game.get("Date")),
        ("Round", game.get("Round")),
        ("White", white),
        ("Black", black),
        ("Result", game.get("Result")),
    ]
    # A custom start position (Studies allow one) must ride in the headers or the
    # viewer replays the moves from the standard start.
    setup_fen = str(game.get("SetupFEN") or "").strip()
    if setup_fen:
        headers += [("FEN", setup_fen), ("SetUp", "1")]
    # PGN tag values must escape backslash and double-quote, else an opponent or
    # event name with a quote (e.g. '2025 "Summer" Open') produces a malformed
    # tag pair that breaks the viewer for every board view.
    def esc(v: object) -> str:
        return str(v).replace("\\", "\\\\").replace('"', '\\"')
    head = "".join(f'[{k} "{esc(v)}"]\n' for k, v in headers if str(v or "").strip())
    return f"{head}\n{movetext}".strip()


def game_analysis(game: GameRow) -> GameAnalysis:
    """The Game's engine analysis; an empty one when it has none."""
    analysis = game.get("Analysis")
    if isinstance(analysis, GameAnalysis):
        return analysis
    return GameAnalysis(chapter_url=str(game.get("ChapterURL") or ""))


def board_pgns(game: GameRow, *, player: str, coach_movetext: str | None) -> dict:
    """
    One PGN per board view, None for a view with no content.

    Game is the bare played line.  My Analysis is offered only when the player
    annotated the Chapter (pgn_stats_core.has_my_analysis), Coach only when a coach Chapter matched.
    Engine is the full movetext with its evals and engine variations, present
    only for an analyzed Game.  No recorded moves: every view is None.
    """
    movetext = str(game.get("Movetext") or "")
    if not movetext.strip():
        return {"game": None, "my_analysis": None, "engine": None, "coach": None}
    setup_fen = str(game.get("SetupFEN") or "")
    return {
        "game": game_pgn(game, mainline_movetext(movetext, setup_fen), player),
        "my_analysis": (game_pgn(game, movetext, player)
                        if has_my_analysis(movetext, setup_fen) else None),
        "engine": game_pgn(game, movetext, player) if game_analysis(game).analyzed else None,
        "coach": game_pgn(game, coach_movetext, player) if coach_movetext is not None else None,
    }


def _engine_view(analysis: GameAnalysis, summary: str) -> dict:
    if not analysis.analyzed:
        return {"state": "awaiting_analysis", "ai_summary": "", "win_probability": [],
                "judged_moves": [], "critical_moment": None}

    moves_by_ply = {m.ply: m for m in analysis.moves}

    def judged(mistake) -> dict:
        move = moves_by_ply.get(mistake.ply)
        best = move.best_move if move is not None else None
        return {
            "ply": mistake.ply,
            "move_number": mistake.move_number,
            "san": mistake.san,
            "severity": mistake.severity,
            "best_move": best or None,
            # The refutation line beyond the best move itself.
            "refutation": list(move.refutation_line[1:]) if move is not None and best else [],
        }

    moment = analysis.critical_moment
    critical = None
    if moment is not None:
        move = moves_by_ply.get(moment.ply)
        critical = {
            "ply": moment.ply,
            "move_number": moment.move_number,
            "side": moment.side,
            "san": moment.san,
            "by_player": moment.by_player,
            "headline": moment.headline,
            "eval_before": moment.eval_before,
            "eval_after": moment.eval_after,
            "best_move": move.best_move if move is not None and move.best_move else None,
        }

    return {
        "state": "analyzed",
        "ai_summary": summary,
        "win_probability": [{
            "ply": m.ply,
            "move_number": m.move_number,
            "side": m.side,
            "san": m.san,
            "white_win_pct": round(win_pct_from_cp(m.eval_after * 100.0), 2),
        } for m in analysis.moves],
        "judged_moves": [judged(m) for m in analysis.error_profile],
        "critical_moment": critical,
    }


def _text(value: object) -> str:
    """A header value, "" when unset or '?' (rows the web hides)."""
    text = str(value or "").strip()
    return "" if text == "?" else text


def _metadata(game: Mapping) -> dict:
    return {
        "date": iso_date(game["Date_dt"]),
        "series": _text(game.get("Event")),
        "round": _text(game.get("Round")),
        "color": game["Color"],
        "result": _text(game.get("Result")),
        "termination": _text(game.get("Termination")),
        "player_rating": whole_rating(game.get("PlayerRatingNum")),
        "opponent_rating": whole_rating(game.get("OpponentRatingNum")),
        "eco": _text(game.get("ECO")),
        "opening": _text(game.get("Opening")),
        "moves": optional_int(game.get("FullMoves")),
        "study_name": _text(game.get("StudyName")),
    }


def _uscf_record(game: Mapping) -> dict | None:
    """What USCF officially recorded, or None for an unmatched Game (no USCF
    facts are ever invented, ADR 0003)."""
    if not game.get("UscfMatched"):
        return None
    system = str(game.get("UscfRatingSystem") or "")
    opponent_id = str(game.get("UscfOpponentId") or "")
    uscf_color = str(game.get("UscfColor") or "")
    return {
        "rated_event_id": str(game.get("UscfEventId") or ""),
        "rated_event_name": str(game.get("UscfEventName") or ""),
        "section": str(game.get("UscfSection") or ""),
        "rating_system": system,
        "rating_system_label": USCF_RATING_SYSTEM_LABELS.get(system, system),
        "matched_by": game["UscfMatchedBy"],
        "opponent_name": str(game.get("UscfOpponentName") or ""),
        "opponent_id": opponent_id,
        "opponent_url": uscf_member_url(opponent_id),
        "uscf_color": uscf_color if uscf_color in ("White", "Black") else None,
        "color_conflict": bool(game.get("UscfColorConflict")),
    }


def build_game(game: Mapping, *, player: str, coach_movetext: str | None) -> dict:
    """The Game detail screen for one Game row (``GamePayload``)."""
    return {
        "game": game_summary(game),
        "player_color": game["Color"],
        "forfeit": bool(game.get("Forfeit")),
        "board": board_pgns(game, player=player, coach_movetext=coach_movetext),
        "engine": _engine_view(game_analysis(game), str(game.get("Summary") or "")),
        "metadata": _metadata(game),
        "lessons": list(game.get("Lessons") or []),
        "tags": tags(game.get("Tags") or [], game.get("TagSources")),
        "uscf_record": _uscf_record(game),
    }
