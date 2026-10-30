---
status: accepted
---

# A native iOS client over a versioned JSON API

## Context and Problem Statement

The dashboard is mostly checked from a phone: at the club before a round, between rounds, on the way home. The Plotly Dash app is built for a desktop browser, so on an iPhone the charts are cramped, the filter drawer and Official/Live lens are awkward, and every screen is a page load over club Wi-Fi that often isn't there. How should a native iOS app get its data, sign in, and stay in step with the web app (spec: issue #110)?

## Considered Options

- The iOS app is a client of the existing server, over a versioned JSON API served next to Dash
- Port the cores (stats, USCF matching, engine analysis) to Swift and compute on the device
- Wrap the web app in a WKWebView

## Decision Outcome

Chosen: "client of the existing server", because every Sync, enrichment, match, filter, lens application, and statistic already lives in tested Python, and a second implementation in Swift would drift from it. The phone never talks to Lichess, USCF, or Anthropic, so the "one HTTP boundary per source" invariant is unchanged and no secret (Lichess token, `ANTHROPIC_API_KEY`) leaves the server.

The shape of the API:

- **Same server, same worker.** The API is a Flask blueprint (`api`) on the server Dash already runs on. It reads the same per-user store through the same accessors, so ADR 0005 and ADR 0006 hold unchanged: no new process, no database, and per-request user activation exactly as for Dash callbacks.
- **A read surface, like a page.** A route parses the query string, calls `filters.get_filtered()` once (so the lens is still applied in exactly one place), passes the Games to a pure builder in `payloads`, and serializes. It never fetches, never mutates the store, and never computes stats inline. Where a page assembles data beyond calling a core function, that assembly moves into a core or `payloads` first and the page calls it, so the web and the phone can't drift.
- **One route per screen**, under `/api/v1/`, with the global filters and the lens as query parameters that mirror `FILTER_INPUTS` one to one. Display rules apply in the payload: ratings are whole numbers, every Tag carries its source (`mine` or `engine`), and enrichment fields are always present (unmatched, un-analyzed, or empty, never absent). A Game is addressed by an opaque Game ID, today the last segment of its ChapterURL, the same id the web's `/game/<id>` uses.
- **Bearer-token sign-in.** `POST /api/v1/session` takes the web login's credentials (owner password, guest, or username plus password), runs the same throttle (one table, shared with the web form), and returns a token signed with `SECRET_KEY` that carries the role and username and expires on the web session's 7-day lifetime. The login gate accepts a session cookie or a bearer token, and answers an unauthenticated `/api/*` request with a JSON 401 instead of the login redirect. `auth.can_write()` and `auth.current_user()` resolve a token exactly like a session, so every existing write check covers the API. Tokens are stateless: rotating `SECRET_KEY` signs out every browser and phone at once, which is intended.
- **The contract is an OpenAPI 3.1 document in the repo** (`openapi/v1.json`, bundled from per-screen fragments in `openapi/src/`). It is the single source of truth: Swift types are generated from it, and a server test fails when a route's real response doesn't validate against it. The contract tests record their validated responses as fixtures (`openapi/fixtures/`) that the iOS tests decode, so a server change that breaks a Swift decoder fails the iOS build.
- **Versioning.** Additive changes stay in v1. A breaking change ships as v2 alongside v1 until the TestFlight build that uses v2 is out.
- **Reconciliation stays web-only.** It is a desk task; the app links to it in Safari.

### Consequences

- Good, because the phone and the web show the same numbers by construction: one store, one filter path, one set of cores.
- Good, because the API adds no infrastructure and keeps every existing invariant (single worker, in-memory store, enrichment never a dependency).
- Good, because the contract and its recorded fixtures make drift between server and app a test failure on both sides.
- Bad, because the app needs the server to compute anything new. Offline means reading the last cached responses, never a Sync or a fresh stat.
- Bad, because stateless tokens can't be revoked one at a time; the only revocation is rotating `SECRET_KEY` (or removing the user from `USCF_DASHBOARD_USERS`, which invalidates that user's tokens at the next request).

## Pros and Cons of the Options

### Port the cores to Swift

- Good, because the app could compute offline.
- Bad, because two implementations of every stat, match rule, and analysis parser would drift, and the app would need the Lichess token and the Anthropic key on the device.

### Wrap the web app in a WKWebView

- Good, because it is nearly free.
- Bad, because it keeps every problem it was meant to fix: cramped charts, a web board, and a page load per screen with no offline reading.
