"""
payloads
========
The screen payload builders for the JSON API (ADR 0008).

One module per screen, each a pure function from already-filtered,
lens-applied Games (plus whatever store data the screen needs) to a plain,
JSON-serializable dict: the data a screen shows, never a Plotly figure.  No
Dash or Flask imports, so every builder is callable from a notebook, like the
other cores.  ``common`` holds the shapes every screen shares (the Game
summary row, Tags with their source, whole-number ratings, the Game ID).

The shapes are specified by the OpenAPI document (``openapi/v1.json``); the
contract tests validate every builder's output against it.
"""
