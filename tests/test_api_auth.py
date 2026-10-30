"""
tests/test_api_auth.py
======================
Bearer-token sign-in for the JSON API (ADR 0008).

The phone signs in with the same credentials as the web login, gets a signed,
expiring token, and sends it as ``Authorization: Bearer``.  Tested through a
real Flask server with the gate and the API installed, the way the iOS client
exercises it.  The cookie gate's own behavior is covered, unchanged, by
``test_auth``.
"""
from __future__ import annotations

import time
from unittest import mock

import flask
import pytest

import api
import auth
import data
from user_config import UserRecord, hash_password

OWNER_PW = "owner-pw"


def _users() -> dict[str, UserRecord]:
    def rec(name, pw):
        return UserRecord(username=name, password_hash=hash_password(pw),
                          study_ids=("study-" + name,), coach_study_ids=(),
                          uscf_member_id=None, lichess_token=None)
    return {"daniel": rec("daniel", "hunter2"), "friend": rec("friend", "swordfish")}


def _server(**gate) -> flask.Flask:
    server = flask.Flask(__name__)
    auth.install_auth(server, secret_key="test-secret", secure_cookies=False, **gate)
    api.install(server)

    @server.route("/")
    def home():
        return "home"

    return server


@pytest.fixture()
def owner_client():
    auth._login_fails.clear()
    return _server(owner_password_hash=hash_password(OWNER_PW)).test_client()


@pytest.fixture()
def multi_client():
    auth._login_fails.clear()
    return _server(users=_users()).test_client()


def _sign_in(client, **body):
    return client.post("/api/v1/session", json=body)


def _bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def _token(client, **body) -> str:
    resp = _sign_in(client, **body)
    assert resp.status_code == 200, resp.get_json()
    return resp.get_json()["token"]


class TestUnauthenticated:
    def test_no_token_gets_a_json_401_not_a_redirect(self, owner_client):
        resp = owner_client.get("/api/v1/meta")
        assert resp.status_code == 401
        assert resp.get_json()["error"]["code"] == "unauthenticated"

    def test_tampered_token_is_401(self, owner_client):
        token = _token(owner_client, password=OWNER_PW)
        forged = token[:-2] + ("AA" if token[-2:] != "AA" else "BB")
        resp = owner_client.get("/api/v1/meta", headers=_bearer(forged))
        assert resp.status_code == 401
        assert resp.get_json()["error"]["code"] == "unauthenticated"

    def test_expired_token_is_401(self, owner_client):
        token = _token(owner_client, password=OWNER_PW)
        later = time.time() + auth.TOKEN_LIFETIME.total_seconds() + 60
        with mock.patch("itsdangerous.timed.time.time", return_value=later):
            resp = owner_client.get("/api/v1/meta", headers=_bearer(token))
        assert resp.status_code == 401

    def test_token_from_another_secret_is_401(self, owner_client):
        other = _server(owner_password_hash=hash_password(OWNER_PW))
        other.secret_key = "another-secret"
        token = _token(other.test_client(), password=OWNER_PW)
        assert owner_client.get("/api/v1/meta", headers=_bearer(token)).status_code == 401

    def test_web_pages_still_redirect_to_login(self, owner_client):
        resp = owner_client.get("/")
        assert resp.status_code == 302
        assert "/login" in resp.headers["Location"]


class TestOwnerMode:
    def test_owner_password_gets_an_owner_token(self, owner_client):
        resp = _sign_in(owner_client, password=OWNER_PW)
        body = resp.get_json()
        assert resp.status_code == 200
        assert body["role"] == "owner" and body["can_write"] is True
        assert body["username"] is None
        meta = owner_client.get("/api/v1/meta", headers=_bearer(body["token"]))
        assert meta.status_code == 200
        assert meta.get_json()["session"] == {
            "role": "owner", "username": None, "can_write": True}

    def test_guest_gets_a_read_only_token(self, owner_client):
        token = _token(owner_client, guest=True)
        meta = owner_client.get("/api/v1/meta", headers=_bearer(token))
        assert meta.get_json()["session"]["role"] == "guest"
        assert meta.get_json()["session"]["can_write"] is False

    def test_guest_calling_sync_is_403(self, owner_client):
        token = _token(owner_client, guest=True)
        with mock.patch.object(data, "refresh") as refresh:
            resp = owner_client.post("/api/v1/sync", headers=_bearer(token))
        assert resp.status_code == 403
        assert resp.get_json()["error"]["code"] == "forbidden"
        refresh.assert_not_called()

    def test_wrong_password_is_401(self, owner_client):
        resp = _sign_in(owner_client, password="nope")
        assert resp.status_code == 401
        assert resp.get_json()["error"]["code"] == "unauthenticated"
        assert "token" not in resp.get_json()

    def test_token_reaches_the_api_without_a_cookie(self, owner_client):
        token = _token(owner_client, password=OWNER_PW)
        fresh = owner_client.application.test_client()  # no cookie jar
        assert fresh.get("/api/v1/meta", headers=_bearer(token)).status_code == 200

    def test_a_web_session_cookie_also_reaches_the_api(self, owner_client):
        owner_client.post("/login", data={"password": OWNER_PW})
        assert owner_client.get("/api/v1/meta").status_code == 200

    def test_token_expiry_matches_the_web_session(self):
        assert auth.TOKEN_LIFETIME.days == 7


class TestThrottle:
    def test_wrong_passwords_are_throttled_like_the_web_login(self, owner_client):
        for _ in range(auth._THROTTLE_MAX_FAILS):
            assert _sign_in(owner_client, password="wrong").status_code == 401
        resp = _sign_in(owner_client, password=OWNER_PW)
        assert resp.status_code == 429
        assert resp.get_json()["error"]["code"] == "throttled"

    def test_the_web_and_the_api_share_one_throttle(self, owner_client):
        for _ in range(auth._THROTTLE_MAX_FAILS):
            owner_client.post("/login", data={"password": "wrong"})
        assert _sign_in(owner_client, password=OWNER_PW).status_code == 429


class TestMultiUser:
    def test_user_token_resolves_to_that_user(self, multi_client):
        token = _token(multi_client, username="friend", password="swordfish")
        meta = multi_client.get("/api/v1/meta", headers=_bearer(token)).get_json()
        assert meta["session"] == {"role": "owner", "username": "friend", "can_write": True}

    def test_wrong_password_is_refused(self, multi_client):
        assert _sign_in(multi_client, username="friend", password="x").status_code == 401

    def test_there_is_no_guest(self, multi_client):
        resp = _sign_in(multi_client, guest=True)
        assert resp.status_code == 403
        assert resp.get_json()["error"]["code"] == "forbidden"

    def test_a_token_for_a_removed_user_is_401(self, multi_client):
        token = _token(multi_client, username="friend", password="swordfish")
        gate = multi_client.application.extensions[auth._EXTENSION]
        del gate.users["friend"]
        assert multi_client.get("/api/v1/meta", headers=_bearer(token)).status_code == 401

    def test_each_token_sees_only_its_own_store(self):
        """Through the real gated app, a token activates its own user's store."""
        import pandas as pd

        from tests.conftest import preserve_dash_callbacks

        data.reset()
        with mock.patch("data.sync_user"):  # don't really Sync at build
            from app import build_app
            _dash, server = build_app([], users=_users(), secret_key="a-real-secret")
        def games(*urls):
            return pd.DataFrame({
                "ChapterURL": list(urls), "Termination": "Normal", "Event": "Ladder",
                "Date_dt": pd.Timestamp("2026-01-01"), "FullMoves": 30})

        data._registry["daniel"].df = games("d1")
        data._registry["daniel"].initialized = True
        data._registry["friend"].df = games("f1", "f2")
        data._registry["friend"].initialized = True
        try:
            with preserve_dash_callbacks():
                client = server.test_client()
                for username, pw, total in [("daniel", "hunter2", 1),
                                            ("friend", "swordfish", 2)]:
                    token = _token(client, username=username, password=pw)
                    meta = client.get("/api/v1/meta", headers=_bearer(token))
                    assert meta.status_code == 200
                    assert meta.get_json()["games_total"] == total
                    assert meta.get_json()["session"]["username"] == username
        finally:
            data.reset()


class TestUngated:
    def test_an_ungated_server_signs_anyone_in_as_owner(self):
        server = flask.Flask(__name__)
        api.install(server)
        client = server.test_client()
        body = _sign_in(client).get_json()
        assert body["role"] == "owner" and body["can_write"] is True
        # The token is decorative here: an ungated API needs none.
        assert client.get("/api/v1/meta").status_code == 200

    def test_malformed_body_is_a_400(self, owner_client):
        resp = owner_client.post("/api/v1/session", data="not json",
                                 content_type="text/plain")
        assert resp.status_code == 400
        assert resp.get_json()["error"]["code"] == "bad_request"
