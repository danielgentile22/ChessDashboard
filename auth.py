"""
auth.py
=======
The login gate and the owner/guest role check.

A lightweight session gate over the Flask/Dash server, installed as a Flask
``before_request`` hook that bounces everything except the login page and
static assets to ``/login`` until a valid session exists.

It runs in one of two modes:

* **Owner mode** (single-user deploy, ``OWNER_PASSWORD_HASH`` set).  The login
  page asks for the owner's password, or offers "Continue as guest".  Guests
  see every page but are read-only: :func:`can_write` is False for them, and
  every callback that changes state or calls a tokened or paid API checks it.
* **Multi-user mode** (``USCF_DASHBOARD_USERS`` set).  Username + password
  against the allow-listed user records; each user owns their own store and
  can write to it.  There is no guest access.

With neither configured the server is ungated and every request can write
(local development, demo mode, and most of the test suite).

Public API
----------
install_auth   Install the gate + login/logout routes on a Flask server.
current_user   The authenticated username for the current request (or None).
current_role   ``OWNER`` / ``GUEST`` for the current request (or None).
can_write      Whether the current request may change state or call a paid API.
is_guest       Whether the current request is a signed-in guest.
Auth           The installed gate's handle.
"""
from __future__ import annotations

import time
from dataclasses import dataclass
from datetime import timedelta

from flask import (
    Flask,
    Response,
    current_app,
    has_request_context,
    redirect,
    request,
    session,
)
from markupsafe import escape
from werkzeug.security import check_password_hash, generate_password_hash

from user_config import UserRecord

OWNER = "owner"
GUEST = "guest"

# An unknown username is checked against this hash so it costs the same scrypt
# work as a known one: no username enumeration by response time.
_DUMMY_HASH = generate_password_hash("*never-a-real-password*")

# Login throttle: after this many failures for one (IP, username) within the
# window, further attempts are refused until the window elapses.  In-memory
# only, so it resets on restart; fine for a throttle.
_THROTTLE_MAX_FAILS = 5
_THROTTLE_WINDOW_S = 300.0
# A per-(ip, user) counter, capped in size; fine for a small allow-list.
_THROTTLE_MAX_KEYS = 4096
_login_fails: dict[tuple[str, str], list[float]] = {}


def _throttled(key: tuple[str, str]) -> bool:
    """True if *key* has too many recent failures: refuse the attempt."""
    now = time.monotonic()
    recent = [t for t in _login_fails.get(key, ()) if now - t < _THROTTLE_WINDOW_S]
    _login_fails[key] = recent
    return len(recent) >= _THROTTLE_MAX_FAILS


def _record_failure(key: tuple[str, str]) -> None:
    now = time.monotonic()
    if len(_login_fails) >= _THROTTLE_MAX_KEYS:
        # Drop keys whose failures have all aged out, so an attacker rotating
        # usernames can't grow the table without bound.
        for stale in [k for k, ts in _login_fails.items()
                      if all(now - t >= _THROTTLE_WINDOW_S for t in ts)]:
            del _login_fails[stale]
    _login_fails.setdefault(key, []).append(now)

# Paths reachable without a session: the login/logout routes, static assets the
# login page needs, Dash's vendored component bundles (static JS, never data),
# and the health check.  Everything else, pages and Dash data callbacks, is
# gated.
_PUBLIC_PREFIXES = (
    "/login",
    "/logout",
    "/assets/",
    "/_dash-component-suites/",
    "/_reload-hash",
    "/_favicon.ico",
)
_PUBLIC_PATHS = ("/health", "/favicon.ico")

# The page description, for search results and link previews.  A gated site
# serves the login page to every crawler, so it carries it too.
DESCRIPTION = (
    "Analytics for over-the-board USCF chess games: Lichess Studies enriched "
    "with official USCF ratings, engine analysis, and AI summaries."
)
_DESCRIPTION = escape(DESCRIPTION)

_USER_KEY = "user"
_ROLE_KEY = "role"
_EXTENSION = "chess_dashboard_auth"


@dataclass
class Auth:
    """The installed gate: who may sign in, and what role a session holds."""

    users: dict[str, UserRecord]
    owner_password_hash: str | None = None

    @property
    def owner_mode(self) -> bool:
        """True for the single-user owner/guest gate."""
        return self.owner_password_hash is not None

    @property
    def enabled(self) -> bool:
        """True when anything is configured; the gate is active only then."""
        return self.owner_mode or bool(self.users)

    def authenticate(self, username: str, password: str) -> UserRecord | None:
        """Multi-user mode: the record for *username* if *password* is correct.

        An unknown username still pays the full scrypt cost against a dummy
        hash, so presence and absence can't be told apart by response time.
        """
        record = self.users.get(username)
        if record is None:
            check_password_hash(_DUMMY_HASH, password)
            return None
        return record if record.verify(password) else None

    def authenticate_owner(self, password: str) -> bool:
        """Owner mode: whether *password* is the owner's."""
        return bool(self.owner_password_hash) and check_password_hash(
            self.owner_password_hash or "", password)

    def role_of(self, sess) -> str | None:
        """The role a session holds, or None if it isn't signed in."""
        if self.owner_mode:
            role = sess.get(_ROLE_KEY)
            return role if role in (OWNER, GUEST) else None
        # Multi-user: every allow-listed user owns their own store.
        return OWNER if sess.get(_USER_KEY) in self.users else None


def _gate() -> Auth | None:
    """The gate installed on the current app, or None if ungated."""
    return current_app.extensions.get(_EXTENSION)


def current_user() -> str | None:
    """The authenticated username for the current request, or None.

    Only multi-user sessions carry a username.  Outside a request context
    (e.g. a background thread) nobody is logged in.
    """
    try:
        return session.get(_USER_KEY)
    except RuntimeError:
        return None


def current_role() -> str | None:
    """``OWNER`` or ``GUEST`` for the current request, or None when the server
    is ungated, the request isn't signed in, or there is no request."""
    if not has_request_context():
        return None
    gate = _gate()
    return gate.role_of(session) if gate is not None else None


def is_guest() -> bool:
    """Whether the current request is a signed-in guest (read-only)."""
    return current_role() == GUEST


def can_write() -> bool:
    """Whether the current request may change state or call a tokened or paid
    API (Sync, Reconciliation dismissals).

    A gated server allows only the owner.  An ungated server allows everyone,
    and so does code running outside a request (startup Sync, tests), since no
    visitor can reach that path.
    """
    if not has_request_context():
        return True
    gate = _gate()
    if gate is None:
        return True
    return gate.role_of(session) == OWNER


def install_auth(
    server: Flask,
    users: dict[str, UserRecord] | None = None,
    *,
    owner_password_hash: str | None = None,
    secret_key: str,
    login_path: str = "/login",
    secure_cookies: bool = True,
) -> Auth:
    """
    Gate *server* behind a login, and register the login/logout routes.

    Pass *owner_password_hash* for the single-user owner/guest gate, or *users*
    for multi-user mode.  The session is signed with *secret_key*; set a
    stable, secret value in production (``SECRET_KEY``) so sessions survive
    restarts and cannot be forged.  *secure_cookies* marks the session cookie
    ``Secure`` (HTTPS-only); pass ``False`` only for local HTTP dev.
    """
    users = users or {}
    if (owner_password_hash is None) == (not users):
        raise ValueError("install_auth needs exactly one of users or owner_password_hash")

    server.secret_key = secret_key
    # HTTPS-only in production, never readable from JS, SameSite=Lax against
    # cross-site POSTs, and a bounded lifetime so a leaked cookie expires.
    server.config.update(
        SESSION_COOKIE_SECURE=secure_cookies,
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Lax",
        PERMANENT_SESSION_LIFETIME=timedelta(days=7),
    )
    gate = Auth(users, owner_password_hash)
    server.extensions[_EXTENSION] = gate

    def _sign_in(role: str, username: str | None = None):
        session.clear()
        session.permanent = True  # apply PERMANENT_SESSION_LIFETIME
        session[_ROLE_KEY] = role
        if username:
            session[_USER_KEY] = username
        return redirect(_safe_next(request.form.get("next", "")))

    def _page(error: str = "", status: int = 200, next_path: str = "/") -> Response:
        html = _login_page(error=error, next_path=next_path, owner_mode=gate.owner_mode)
        return Response(html, status=status, mimetype="text/html")

    @server.before_request
    def _require_login():
        path = request.path
        if path in _PUBLIC_PATHS or any(path.startswith(p) for p in _PUBLIC_PREFIXES):
            return None
        if gate.role_of(session) is not None:
            return None
        return redirect(login_path)

    @server.route(login_path, methods=["GET", "POST"])
    def login():
        if request.method == "POST":
            username = "" if gate.owner_mode else request.form.get("username", "")
            password = request.form.get("password", "")
            throttle_key = (request.remote_addr or "?", username or OWNER)
            if _throttled(throttle_key):
                return _page("Too many attempts. Wait a few minutes.", 429)
            if gate.owner_mode:
                ok = gate.authenticate_owner(password)
            else:
                ok = gate.authenticate(username, password) is not None
            if ok:
                _login_fails.pop(throttle_key, None)
                return _sign_in(OWNER, username or None)
            _record_failure(throttle_key)
            wrong = "Wrong password." if gate.owner_mode else "Wrong username or password."
            return _page(wrong, 401)
        # A guest may come back here to sign in as the owner; the owner is
        # already in, so send them on.
        if gate.role_of(session) == OWNER:
            return redirect("/")
        return _page(next_path=_safe_next(request.args.get("next", "")))

    if gate.owner_mode:
        @server.route(f"{login_path}/guest", methods=["POST"])
        def login_guest():
            return _sign_in(GUEST)

    # POST-only: a GET /logout is CSRF-able (`<img src=".../logout">` would log a
    # user out from any page), so state change requires the shell's logout form.
    @server.route("/logout", methods=["POST"])
    def logout():
        session.clear()
        return redirect(login_path)

    return gate


def _safe_next(raw: str) -> str:
    """A post-login redirect target, restricted to a local path (no open
    redirect to another host).

    Rejects both ``//host`` and the backslash form ``/\\host``: browsers
    normalise ``\\`` to ``/`` per the WHATWG URL spec, so ``/\\evil.com``
    resolves off-site.
    """
    if raw.startswith("/") and not raw.startswith(("//", "/\\")):
        return raw
    return "/"


def _login_page(*, error: str = "", next_path: str = "/", owner_mode: bool = False) -> str:
    """The standalone login page, self-contained so it needs no Dash assets."""
    error_html = (
        f'<p class="login-error">{escape(error)}</p>' if error else ""
    )
    next_input = f'<input type="hidden" name="next" value="{escape(next_path)}">'
    if owner_mode:
        subtitle = "Sign in as the owner, or look around as a guest."
        username_field = ""
        guest_form = f"""
  <form class="login-card login-guest" method="post" action="/login/guest">
    {next_input}
    <button type="submit" class="login-secondary">Continue as guest</button>
    <p class="login-note">Guests see every page and every game, read-only.
      Syncing and dismissing items stay with the owner.</p>
  </form>"""
    else:
        subtitle = "Sign in to see your dashboard."
        username_field = """
    <label for="username">Username</label>
    <input id="username" name="username" autocomplete="username" autofocus required>"""
        guest_form = ""
    password_autofocus = " autofocus" if owner_mode else ""
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="{_DESCRIPTION}">
  <meta property="og:title" content="Chess Dashboard">
  <meta property="og:description" content="{_DESCRIPTION}">
  <meta property="og:type" content="website">
  <title>Sign in | Chess Dashboard</title>
  <style>
    :root {{ color-scheme: dark; }}
    body {{ margin: 0; min-height: 100vh; display: grid; place-content: center;
            gap: 12px; padding: 16px; box-sizing: border-box;
            background: #0b0d12; color: #e7e9ee;
            font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }}
    .login-card {{ width: min(320px, calc(100vw - 32px)); box-sizing: border-box;
                   padding: 32px; border-radius: 16px;
                   background: #151922; box-shadow: 0 12px 40px rgba(0,0,0,.45); }}
    .login-title {{ margin: 0 0 4px; font-size: 22px; font-weight: 650; }}
    .login-sub {{ margin: 0 0 24px; color: #9aa0ad; font-size: 14px; }}
    label {{ display: block; margin: 0 0 6px; font-size: 13px; color: #9aa0ad; }}
    input {{ width: 100%; box-sizing: border-box; margin: 0 0 16px; padding: 10px 12px;
             border: 1px solid #2a2f3a; border-radius: 10px; background: #0e1117;
             color: #e7e9ee; font-size: 15px; }}
    input:focus {{ outline: 2px solid #4c8bf5; border-color: transparent; }}
    button {{ width: 100%; padding: 11px; border: 0; border-radius: 10px; cursor: pointer;
              background: #4c8bf5; color: #fff; font-size: 15px; font-weight: 600; }}
    button:hover {{ background: #3f7ae0; }}
    .login-guest {{ padding: 20px 32px; }}
    .login-secondary {{ background: transparent; color: #e7e9ee;
                        border: 1px solid #2a2f3a; }}
    .login-secondary:hover {{ background: #1d222d; }}
    .login-note {{ margin: 12px 0 0; color: #9aa0ad; font-size: 13px; }}
    .login-error {{ margin: 0 0 16px; padding: 9px 12px; border-radius: 8px;
                    background: rgba(229,72,77,.14); color: #ff8b8f; font-size: 13px; }}
  </style>
</head>
<body>
  <form class="login-card" method="post" action="/login">
    <h1 class="login-title">Chess Dashboard</h1>
    <p class="login-sub">{subtitle}</p>
    {error_html}
    {next_input}{username_field}
    <label for="password">Password</label>
    <input id="password" name="password" type="password"
           autocomplete="current-password" required{password_autofocus}>
    <button type="submit">Sign in</button>
  </form>{guest_form}
</body>
</html>"""
