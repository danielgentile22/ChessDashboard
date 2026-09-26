"""
tests/test_auth.py
==================
The login gate.

An unauthenticated request never reaches a page; a valid login is accepted and
resolves to the right user; a wrong password is refused; the session persists
across navigation.  Tested through the real Flask server with its test client,
the way a browser exercises it.
"""
from __future__ import annotations

from unittest import mock

import flask
import pytest

import auth
from user_config import UserRecord, hash_password


def _users() -> dict[str, UserRecord]:
    def rec(name, pw):
        return UserRecord(username=name, password_hash=hash_password(pw),
                          study_ids=("study-" + name,), coach_study_ids=(),
                          uscf_member_id=None, lichess_token=None)
    return {"daniel": rec("daniel", "hunter2"), "friend": rec("friend", "swordfish")}


@pytest.fixture()
def app():
    """A minimal Flask server with the gate installed and one protected route."""
    server = flask.Flask(__name__)
    # secure_cookies=False so the HTTP test client keeps the session cookie
    # (production sets it via secure_cookies=not DEBUG).
    auth.install_auth(server, _users(), secret_key="test-secret", secure_cookies=False)

    @server.route("/")
    def home():
        return f"hello {auth.current_user()}"

    @server.route("/health")
    def health():
        return "ok"

    return server


@pytest.fixture()
def client(app):
    return app.test_client()


def _login(client, username, password):
    return client.post("/login", data={"username": username, "password": password})


# ---------------------------------------------------------------------------
# The gate
# ---------------------------------------------------------------------------

class TestGate:
    def test_unauthenticated_request_is_redirected_to_login(self, client):
        resp = client.get("/")
        assert resp.status_code == 302
        assert "/login" in resp.headers["Location"]

    def test_login_page_is_reachable_without_auth(self, client):
        resp = client.get("/login")
        assert resp.status_code == 200
        assert b"password" in resp.data.lower()

    def test_health_check_is_not_gated(self, client):
        assert client.get("/health").status_code == 200

    def test_assets_are_not_gated(self, app):
        # Static assets the login page needs must be reachable pre-auth.
        client = app.test_client()
        # /assets/ is whitelisted even though this minimal app serves nothing there
        resp = client.get("/assets/whatever.css")
        assert resp.status_code != 302  # not bounced to login (404 is fine)


# ---------------------------------------------------------------------------
# Logging in
# ---------------------------------------------------------------------------

class TestLogin:
    def test_valid_login_is_accepted_and_reaches_the_page(self, client):
        resp = _login(client, "daniel", "hunter2")
        assert resp.status_code == 302  # redirected into the app
        page = client.get("/")
        assert page.status_code == 200
        assert b"hello daniel" in page.data

    def test_login_resolves_to_the_right_user(self, client):
        _login(client, "friend", "swordfish")
        assert b"hello friend" in client.get("/").data

    def test_wrong_password_is_refused(self, client):
        resp = _login(client, "daniel", "nope")
        # not redirected into the app, and the page stays gated
        assert b"hello daniel" not in resp.data
        assert client.get("/").status_code == 302

    def test_unknown_user_is_refused(self, client):
        _login(client, "stranger", "whatever")
        assert client.get("/").status_code == 302

    def test_session_persists_across_navigation(self, client):
        _login(client, "daniel", "hunter2")
        # Several page loads on the same client (one browser session)
        assert client.get("/").status_code == 200
        assert client.get("/").status_code == 200

    def test_repeated_failures_are_throttled(self, client):
        auth._login_fails.clear()
        for _ in range(auth._THROTTLE_MAX_FAILS):
            assert _login(client, "daniel", "wrong").status_code == 401
        # Next attempt is refused up-front (429), even with the right password
        assert _login(client, "daniel", "hunter2").status_code == 429
        auth._login_fails.clear()


# ---------------------------------------------------------------------------
# Logging out
# ---------------------------------------------------------------------------

class TestLogout:
    def test_logout_clears_the_session(self, client):
        _login(client, "daniel", "hunter2")
        assert client.get("/").status_code == 200
        client.post("/logout")  # POST-only: GET /logout is CSRF-able
        assert client.get("/").status_code == 302

    def test_logout_get_is_rejected(self, client):
        _login(client, "daniel", "hunter2")
        assert client.get("/logout").status_code == 405  # no CSRF-able GET


# ---------------------------------------------------------------------------
# Enablement
# ---------------------------------------------------------------------------

class TestEnablement:
    def test_auth_is_enabled_when_users_are_configured(self):
        a = auth.Auth(_users())
        assert a.enabled is True

    def test_auth_is_disabled_with_no_users(self):
        assert auth.Auth({}).enabled is False


# ---------------------------------------------------------------------------
# The gate, wired into the real Dash app via build_app
# ---------------------------------------------------------------------------

class TestBuildAppGate:
    @pytest.mark.parametrize("bad_key", ["dev-insecure-change-me", "   ", ""])
    def test_multi_user_refuses_forgeable_secret_key(self, bad_key):
        """Multi-user auth won't boot on the public default or a blank key —
        both make session cookies forgeable/unsignable."""
        import data

        data.reset()
        with mock.patch("data.sync_user"):
            from app import build_app
            with pytest.raises(RuntimeError, match="(?i)secret_key"):
                build_app([], users=_users(), secret_key=bad_key)
        data.reset()

    def test_single_user_boots_on_default_key(self):
        """The refusal must NOT bite ungated single-user mode."""
        import data
        from tests.conftest import (
            SAMPLE_PGN,
            preserve_dash_callbacks,
            stub_ui_sources,
        )

        data.reset()
        with stub_ui_sources(SAMPLE_PGN):
            from app import build_app
            _dash_app, server = build_app(
                ["teststudy"], player_name="P", secret_key="dev-insecure-change-me")
        with preserve_dash_callbacks():
            assert server.test_client().get("/").status_code == 200
        data.reset()

    def test_built_app_gates_pages_when_users_configured(self):
        """A real app built with users refuses an unauthenticated page request
        but lets a valid login through to the Dash page content."""
        import data
        from tests.conftest import (
            SAMPLE_PGN,
            preserve_dash_callbacks,
            stub_ui_sources,
        )

        data.reset()
        with stub_ui_sources(SAMPLE_PGN), mock.patch("data.sync_user"):
            from app import build_app
            _dash_app, server = build_app(
                ["teststudy"], player_name="Test Player",
                users=_users(), secret_key="test-secret",
            )
        # build_app has populated Dash's global callback list; snapshot it now so
        # the requests below (which drain it) can't steal ui_app's callbacks.
        # https base_url: build_app sets Secure cookies (not DEBUG), so the
        # session only round-trips over HTTPS — the way Fly serves it.
        https = {"base_url": "https://localhost"}
        with preserve_dash_callbacks(), mock.patch("data.sync_user"):
            client = server.test_client()
            # Unauthenticated → bounced to login, never the page
            assert client.get("/", **https).status_code == 302
            # The login page itself is reachable pre-auth
            assert client.get("/login", **https).status_code == 200
            # Valid login → the Dash index renders
            client.post("/login", data={"username": "daniel", "password": "hunter2"},
                        **https)
            assert client.get("/", **https).status_code == 200
        data.reset()

    def test_built_app_is_ungated_without_users(self):
        """With no users the dashboard runs as before — no login gate."""
        import data
        from tests.conftest import (
            SAMPLE_PGN,
            preserve_dash_callbacks,
            stub_ui_sources,
        )

        data.reset()
        with stub_ui_sources(SAMPLE_PGN):
            from app import build_app
            _dash_app, server = build_app(["teststudy"], player_name="Test Player")
        with preserve_dash_callbacks():
            assert server.test_client().get("/").status_code == 200
        data.reset()


# ---------------------------------------------------------------------------
# Per-user isolation through the gated app
# ---------------------------------------------------------------------------

class TestGatedIsolation:
    def test_each_logged_in_user_activates_their_own_store(self, tmp_path):
        """Through the real gated server, the request's authenticated user is
        the store every accessor resolves to — never another user's."""
        import pandas as pd

        import data
        from tests.conftest import preserve_dash_callbacks

        users = _users()  # daniel + friend
        data.reset()
        with mock.patch("data.sync_user"):  # don't really Sync at build
            from app import build_app
            _dash_app, server = build_app([], users=users, secret_key="test-secret")
        # Give the two stores distinct, recognisable data.
        data._registry["daniel"].df = pd.DataFrame({"ChapterURL": ["d1"]})
        data._registry["daniel"].initialized = True
        data._registry["friend"].df = pd.DataFrame({"ChapterURL": ["f1", "f2"]})
        data._registry["friend"].initialized = True

        try:
            # build_app populated Dash's global callback list; snapshot it so the
            # requests below (which drain it) don't steal ui_app's callbacks.
            with preserve_dash_callbacks():
                # The before_request hook resolves the session user and activates
                # that user's store — so each user's accessor reads only theirs.
                for username, expected in [("daniel", ["d1"]), ("friend", ["f1", "f2"])]:
                    with server.test_request_context("/"):
                        from flask import session
                        session["user"] = username
                        server.preprocess_request()
                        assert list(data.get_df()["ChapterURL"]) == expected
        finally:
            data.reset()


# ---------------------------------------------------------------------------
# The post-login `next` redirect — the open-redirect guard (_safe_next).
# A local path is honored; `//host`, an absolute URL, or the backslash form
# `/\host` (browsers normalise `\`→`/`) all fall back to `/`.
# ---------------------------------------------------------------------------

class TestNextRedirect:
    def _login_next(self, client, nxt):
        return client.post("/login", data={
            "username": "daniel", "password": "hunter2", "next": nxt})

    def test_a_local_next_is_honored_after_login(self, client):
        resp = self._login_next(client, "/trends")
        assert resp.status_code == 302
        assert resp.headers["Location"] == "/trends"

    def test_a_protocol_relative_next_falls_back_to_root(self, client):
        assert self._login_next(client, "//evil.example").headers["Location"] == "/"

    def test_an_absolute_url_next_falls_back_to_root(self, client):
        resp = self._login_next(client, "https://evil.example/x")
        assert resp.headers["Location"] == "/"

    def test_a_backslash_host_next_falls_back_to_root(self, client):
        assert self._login_next(client, "/\\evil.com").headers["Location"] == "/"

    def test_the_login_form_carries_the_escaped_local_next(self, client):
        assert b'name="next" value="/trends"' in client.get("/login?next=/trends").data

    def test_the_login_form_sanitizes_an_off_site_next(self, client):
        assert b'name="next" value="/"' in client.get("/login?next=//evil.example").data


# ---------------------------------------------------------------------------
# Owner mode: the single-user owner password + "Continue as guest"
# ---------------------------------------------------------------------------

_OWNER_PW = "correct horse"


@pytest.fixture()
def owner_app():
    """A minimal Flask server behind the owner/guest gate."""
    server = flask.Flask(__name__)
    auth.install_auth(server, owner_password_hash=hash_password(_OWNER_PW),
                      secret_key="test-secret", secure_cookies=False)

    @server.route("/")
    def home():
        return f"role={auth.current_role()} write={auth.can_write()}"

    return server


@pytest.fixture()
def owner_client(owner_app):
    auth._login_fails.clear()
    yield owner_app.test_client()
    auth._login_fails.clear()


class TestOwnerMode:
    def test_unauthenticated_request_is_redirected_to_login(self, owner_client):
        assert owner_client.get("/").status_code == 302

    def test_login_page_offers_password_and_guest(self, owner_client):
        page = owner_client.get("/login").data
        assert b'name="password"' in page
        assert b'name="username"' not in page
        assert b'action="/login/guest"' in page
        assert b"Continue as guest" in page

    def test_owner_password_signs_in_as_owner(self, owner_client):
        resp = owner_client.post("/login", data={"password": _OWNER_PW})
        assert resp.status_code == 302
        assert owner_client.get("/").data == b"role=owner write=True"

    def test_wrong_password_is_refused(self, owner_client):
        resp = owner_client.post("/login", data={"password": "nope"})
        assert resp.status_code == 401
        assert owner_client.get("/").status_code == 302

    def test_wrong_passwords_are_throttled(self, owner_client):
        for _ in range(auth._THROTTLE_MAX_FAILS):
            owner_client.post("/login", data={"password": "nope"})
        assert owner_client.post("/login", data={"password": _OWNER_PW}).status_code == 429

    def test_guest_can_read_but_not_write(self, owner_client):
        resp = owner_client.post("/login/guest")
        assert resp.status_code == 302
        assert owner_client.get("/").data == b"role=guest write=False"

    def test_guest_can_still_reach_the_login_page_to_sign_in(self, owner_client):
        owner_client.post("/login/guest")
        assert owner_client.get("/login").status_code == 200
        owner_client.post("/login", data={"password": _OWNER_PW})
        assert owner_client.get("/").data == b"role=owner write=True"

    def test_guest_login_is_get_proof(self, owner_client):
        assert owner_client.get("/login/guest").status_code == 405

    def test_logout_ends_a_guest_session(self, owner_client):
        owner_client.post("/login/guest")
        owner_client.post("/logout")
        assert owner_client.get("/").status_code == 302

    def test_a_forged_role_value_is_not_a_session(self, owner_app):
        client = owner_app.test_client()
        with client.session_transaction() as sess:
            sess["role"] = "admin"
        assert client.get("/").status_code == 302

    def test_multi_user_mode_has_no_guest_route(self, client):
        assert client.post("/login/guest").status_code == 404
        assert client.get("/").status_code == 302

    def test_multi_user_login_can_write(self, app):
        with app.test_request_context("/"):
            flask.session["user"] = "daniel"
            assert auth.can_write() is True
            assert auth.current_role() == auth.OWNER

    def test_install_needs_exactly_one_mode(self):
        with pytest.raises(ValueError):
            auth.install_auth(flask.Flask(__name__), secret_key="k")
        with pytest.raises(ValueError):
            auth.install_auth(flask.Flask(__name__), _users(),
                              owner_password_hash="x$y$z", secret_key="k")

    def test_ungated_server_can_write(self):
        with flask.Flask(__name__).test_request_context("/"):
            assert auth.can_write() is True
            assert auth.current_role() is None


# ---------------------------------------------------------------------------
# Role enforcement on the callbacks that write or call tokened / paid APIs.
# The buttons are hidden for guests, but the check must hold server-side too.
# ---------------------------------------------------------------------------

class TestGuestIsReadOnly:
    def _as(self, owner_app, role):
        ctx = owner_app.test_request_context("/")
        ctx.push()
        flask.session["role"] = role
        return ctx

    def test_guest_sync_never_reaches_refresh(self, ui_app, owner_app):
        from shell import run_sync

        ctx = self._as(owner_app, auth.GUEST)
        try:
            with mock.patch("data.refresh") as refresh:
                store, is_open, header, *_ = run_sync(1, {"seq": 0, "new_games": 0})
            refresh.assert_not_called()
            assert header == "Read-only"
            assert is_open is True
        finally:
            ctx.pop()

    def test_owner_sync_does_refresh(self, ui_app, ui_data, owner_app):
        from shell import run_sync

        ctx = self._as(owner_app, auth.OWNER)
        try:
            with mock.patch("data.refresh",
                            return_value=mock.Mock(status="error", error="x")) as refresh:
                run_sync(1, {"seq": 0, "new_games": 0})
            refresh.assert_called_once()
        finally:
            ctx.pop()

    def test_guest_dismiss_never_writes(self, ui_app, owner_app):
        from dash import no_update

        from pages.reconciliation import dismiss_entry

        ctx = self._as(owner_app, auth.GUEST)
        try:
            with mock.patch("data.dismiss_reconciliation_entry") as dismiss, \
                 mock.patch("pages.reconciliation.ctx") as cb_ctx:
                cb_ctx.triggered_id = {"type": "reconcile-dismiss", "index": "e1"}
                assert dismiss_entry([1], 0) == (no_update, no_update)
            dismiss.assert_not_called()
        finally:
            ctx.pop()

    def test_owner_dismiss_writes(self, ui_app, ui_data, owner_app):
        from pages.reconciliation import dismiss_entry

        ctx = self._as(owner_app, auth.OWNER)
        try:
            with mock.patch("data.dismiss_reconciliation_entry") as dismiss, \
                 mock.patch("pages.reconciliation.ctx") as cb_ctx:
                cb_ctx.triggered_id = {"type": "reconcile-dismiss", "index": "e1"}
                dismiss_entry([1], 0)
            dismiss.assert_called_once_with("e1")
        finally:
            ctx.pop()

    def test_guest_sees_no_dismiss_buttons_or_sync(self, ui_app, ui_data, owner_app):
        import data
        import shell
        from pages.reconciliation import _render_entries

        ctx = self._as(owner_app, auth.GUEST)
        try:
            rendered = str(_render_entries(data.get_reconciliation(), []))
            header = str(shell._header("P", guest=True))
        finally:
            ctx.pop()
        assert "reconcile-dismiss" not in rendered
        assert "Read-only guest view" in rendered
        assert "Guest · read-only" in header
        assert "hidden=True" in header


    def test_owner_sees_sign_out_not_the_guest_badge(self, ui_app, owner_app):
        import shell

        ctx = self._as(owner_app, auth.OWNER)
        try:
            header = str(shell._header("P", guest=auth.is_guest()))
        finally:
            ctx.pop()
        assert "Sign out" in header
        assert "Guest · read-only" not in header


class TestBuiltAppOwnerGate:
    def _build(self, **kw):
        import data
        from tests.conftest import SAMPLE_PGN, stub_ui_sources

        data.reset()
        with stub_ui_sources(SAMPLE_PGN):
            from app import build_app
            return build_app(["teststudy"], player_name="Test Player", **kw)

    def test_owner_hash_gates_the_real_app(self):
        import data
        from tests.conftest import preserve_dash_callbacks

        _dash_app, server = self._build(
            owner_password_hash=hash_password(_OWNER_PW), secret_key="test-secret")
        https = {"base_url": "https://localhost"}
        try:
            with preserve_dash_callbacks():
                client = server.test_client()
                assert client.get("/", **https).status_code == 302
                client.post("/login/guest", **https)
                assert client.get("/", **https).status_code == 200
                # A guest firing the Sync callback by hand gets the read-only
                # toast, and no Sync runs.
                body = {
                    "output": "..sync-store.data...sync-toast.is_open..."
                              "sync-toast.header...sync-toast.icon..."
                              "sync-toast.children...celebration-zone.children..",
                    "outputs": [{"id": i, "property": p} for i, p in [
                        ("sync-store", "data"), ("sync-toast", "is_open"),
                        ("sync-toast", "header"), ("sync-toast", "icon"),
                        ("sync-toast", "children"), ("celebration-zone", "children")]],
                    "inputs": [{"id": "sync-button", "property": "n_clicks", "value": 1}],
                    "state": [{"id": "sync-store", "property": "data",
                               "value": {"seq": 0, "new_games": 0}}],
                    "changedPropIds": ["sync-button.n_clicks"],
                }
                with mock.patch("data.refresh") as refresh:
                    resp = client.post("/_dash-update-component", json=body, **https)
                refresh.assert_not_called()
                assert resp.status_code == 200
                assert b"Read-only" in resp.data
        finally:
            data.reset()

    def test_owner_gate_refuses_default_secret_key(self):
        with pytest.raises(RuntimeError, match="(?i)secret_key"):
            self._build(owner_password_hash=hash_password(_OWNER_PW),
                        secret_key="dev-insecure-change-me")

    def test_owner_gate_refuses_a_plaintext_password(self):
        with pytest.raises(RuntimeError, match="OWNER_PASSWORD_HASH"):
            self._build(owner_password_hash="hunter2", secret_key="test-secret")

    def test_demo_mode_stays_ungated(self, tmp_path):
        import data
        from config import config
        from tests.conftest import preserve_dash_callbacks

        data.reset()
        from app import build_app
        _dash_app, server = build_app(
            [], cache_path=config.DEMO_CACHE_PATH, demo_mode=True,
            owner_password_hash=hash_password(_OWNER_PW), secret_key="test-secret")
        try:
            with preserve_dash_callbacks():
                assert server.test_client().get("/").status_code == 200
        finally:
            data.reset()
