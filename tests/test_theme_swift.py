"""
tests/test_theme_swift.py
=========================
The iOS app's color tokens are generated from ``styles.THEME`` (the registry
the CSS ``:root`` block and the Plotly theme read), so the phone and the web
can't drift on color.  These tests fail when the checked-in Swift is stale.
Fix: ``.venv/bin/python ios/scripts/gen_theme.py``.
"""
from __future__ import annotations

import importlib.util
import re
from pathlib import Path

import styles

_SPEC = importlib.util.spec_from_file_location(
    "gen_theme", Path(__file__).resolve().parent.parent / "ios" / "scripts" / "gen_theme.py"
)
gen_theme = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(gen_theme)


def test_generated_swift_matches_theme():
    assert gen_theme.OUT.read_text() == gen_theme.render(styles.THEME), (
        "ThemeTokens.generated.swift is stale: run .venv/bin/python ios/scripts/gen_theme.py")


def test_every_color_token_is_emitted():
    swift = gen_theme.OUT.read_text()
    color_tokens = [k for k, v in styles.THEME.items()
                    if v.startswith("#") or v.startswith("rgba(")]
    assert color_tokens, "THEME has no color tokens?"
    for token in color_tokens:
        assert f"// {token}: " in swift, f"{token} missing from the Swift theme"


def test_values_round_trip():
    """A hex and an rgba token come out as the same channels the web uses."""
    swift = gen_theme.render({"--cs-win": "#30d158", "--cs-border": "rgba(84,84,88,.5)",
                              "--cs-radius": "12px", "--cs-font-body": "-apple-system"})
    assert re.search(r"static let win = ThemeColor\(red: 48, green: 209, blue: 88, alpha: 1\)",
                     swift)
    assert "static let border = ThemeColor(red: 84, green: 84, blue: 88, alpha: 0.5)" in swift
    assert "static let radius: CGFloat = 12" in swift
    assert "apple-system" not in swift


def test_check_mode_flags_staleness(tmp_path, monkeypatch):
    stale = tmp_path / "Theme.swift"
    stale.write_text("// old\n")
    monkeypatch.setattr(gen_theme, "OUT", stale)
    assert gen_theme.main(["--check"]) == 1
    assert gen_theme.main([]) == 0
    assert gen_theme.main(["--check"]) == 0
