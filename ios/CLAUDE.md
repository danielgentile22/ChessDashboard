# iOS app (`ios/`)

## Purpose
The native iPhone client (ADR 0008). A client of the deployed server's
`/api/v1/` JSON API and nothing else: it never talks to Lichess, USCF, or
Anthropic, never computes a stat, and holds no source of truth. Filters, the
Official/Live lens, Sync, and every number come from the server; the phone
renders them, caches the last responses, and links to the web for web-only
surfaces (Reconciliation).

SwiftUI, Swift 6 strict concurrency, iOS 18+, iPhone only (portrait and
landscape). XcodeGen spec; the `.xcodeproj` and `ChessDashboard/Info.plist`
are generated and gitignored.

## Layout

| Path | Owns |
|---|---|
| `project.yml` | XcodeGen spec: app target `ChessDashboard` (bundle `dev.danielgentile.chessdashboard`, team 58N856BAX8), the scheme whose test action runs the package tests. |
| `Config/Base.xcconfig` | `CD_BASE_URL` per configuration (Release `https://chess-dashboard.fly.dev/api/v1/`, Debug `http://localhost:8050/api/v1/`), read from Info.plist as `CDBaseURL`. Optional gitignored `Local.xcconfig` overrides it (copy `Local.xcconfig.example`). |
| `ChessDashboard/` | The app target: views only. `App/` (entry point, root, tab bar, More), `Components/` (screen chrome, filter sheet, Tag chip, freshness, offline banner, `ScreenState`, `ChessBoardView`), `Screens/`. |
| `ChessDashboardKit/` | Swift package with everything testable. No UIKit; `swift test` runs it on the Mac in seconds. One dependency: ChessKit (`exact: "0.17.0"`), for chess rules only. |
| `scripts/gen_api_types.py` | Swift types from `openapi/v1.json` (checked in as `API/APITypes.generated.swift`). |
| `scripts/gen_theme.py` | Swift color tokens from `styles.THEME` (checked in as `Theme/ThemeTokens.generated.swift`). |
| `scripts/make_app_icon.swift` | Draws `ChessDashboard/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (CoreGraphics, opaque 1024 px). |
| `testflight.sh`, `ExportOptions.plist` | Archive, sign (manual: the distribution certificate in `tvhome-signing.keychain-db`, profile "Chess Dashboard App Store"), export, and upload to TestFlight; `--no-upload` stops at the `.ipa`. Reads the repo-root `.env` (`ENV_FILE` overrides, e.g. from a worktree). |

Inside `ChessDashboardKit/Sources/ChessDashboardKit/`:

| Path | Owns |
|---|---|
| `API/APITypes.generated.swift` | `API.*` (every schema, namespaced so `API.Color` never meets SwiftUI's `Color`), `Endpoints.*` (one factory per operation), `API.responseTypes`, `API.specDigest`. |
| `API/DashboardAPI.swift` | **The seam.** `protocol DashboardAPI { data(for: APIRequest) }` plus `send(_:)`, the one decode path, and `APIError`. |
| `API/LiveAPIClient.swift` | The only HTTP: URLSession, bearer token from the `CredentialStore`, error mapping. `SessionGuard` turns any `.unauthenticated` into "back to sign-in". |
| `API/FixtureAPIClient.swift` | Answers from `openapi/fixtures/*.json` for tests and previews; can fail any operation (offline, 401, 403). |
| `Session/` | `Session`, `CredentialStore` (Keychain, in-memory), `SessionStore` (sign-in, guest, sign-out, expiry). |
| `Filters/FilterState.swift` | The filter state plus lens, its canonical form, presets, summary, and `queryItems`: **the only filter-to-query encoder.** |
| `Filters/FilterStore.swift` | The app-wide observable filter state, persisted in UserDefaults. |
| `Cache/ResponseCache.swift` | Last 2xx body per (route + query, server + user) in Caches. Every failure is "no cache". |
| `Screens/ScreenResource.swift` | `ScreenContext` (what every view model takes) and `ScreenResource` (cached first, then refresh, offline flag, `reload` after a Sync). |
| `Screens/SyncModel.swift` | The owner's Sync: `POST sync`, the toast as `SyncReport` (worded like the web's), `revision` bumped on success so every `screenChrome` reloads its resource, then meta re-fetched. |
| `Board/` | The Game detail board. `PGNTree`: our PGN parser into a flat move tree (variations, pre/post comments, NAGs, FEN starts), every move replayed through ChessKit's `SANParser`/`Board`; navigation (into and out of variations, main line by ply), comment display with `[%...]` commands stripped. `BoardDiagram`: what the board view draws, oriented. ChessKit types never leave the kit. Don't use ChessKit's `PGNParser`/`Game`/`MoveTree`: it rejects a comment before move 1 and returns wrong moves in nested variations. |
| `Display/` | `RatingFormat` (whole numbers), `TagDisplay` (mine vs engine), `FreshnessSummary`, `WebPage` (open on the web), `ISODates`, `ChartDates` (contract days as chart x values at local noon, nearest point for touch-to-read). |
| `Theme/` | `ThemeColor` and the generated `Theme`/`ThemeMetrics`. |
| `AppEnvironment.swift` | Composition root: config, guarded client, session, filters, cache, the shared `meta` resource, `context`, `canSync`, `syncUnavailableReason`, `sync`. |

## Invariants

- **One HTTP boundary.** Only `LiveAPIClient` touches URLSession. Views and
  view models see `DashboardAPI` only, through `ScreenContext`.
- **One filter encoder.** Requests get filters only via
  `FilterState.queryItems`, mirroring `filters.get_filtered()` being the one
  place on the server. Never build filter query items anywhere else. The
  lens rides along on every filtered route; it never hides Games.
- **Generated code is never hand-edited.** Change `openapi/src/*.json`,
  rebundle (`python -m api.contract`), then `make ios-codegen`. Same for
  `styles.THEME`. `tests/test_ios_api_types.py` and `tests/test_theme_swift.py`
  (Python) and `ContractTests` (Swift, via `API.specDigest`) fail when stale.
- **Every recorded fixture decodes.** `ContractTests` decodes every
  `openapi/fixtures/<operationId>[.variant].json` through
  `API.responseTypes[operationId]`, read in place via `#filePath` (works for
  `swift test` and on the simulator). A fixture a server ticket records is
  covered with no Swift change.
- **The cache is disposable.** Keyed by server and user (`Session.cacheScope`),
  wiped on sign-out, never consulted for anything but "show this first".
- **Ratings render through `RatingFormat`**; Tags through `TagChip`/`TagDisplay`
  so mine and engine always look different. Glossary words verbatim in UI copy
  (Game, Series, Rated Event, Lesson, Tag, Official/Live Rating, Sync).
- **401 or expiry routes to sign-in** through `SessionGuard` and
  `SessionStore.sessionEnded()`, never per screen.

## Why a hand-rolled generator, not swift-openapi-generator

The contract uses a small, strict subset (closed objects, string enums, `X or
null`, arrays). A ~300-line script covers it, emits plain `Codable` structs
with no runtime dependency, raises on any construct it doesn't know, and checks
its output in so every contract change is a reviewable Swift diff. Apple's
generator would add a build plugin, two runtime packages, and its own client
types, and its generated names (`Components.Schemas.X`, `Operations.Y.Output`)
would leak into every screen.

## Adding a screen (#117-#120)

One screen = one view model in the kit + one view in the app.

1. **View model** in `ChessDashboardKit/Sources/ChessDashboardKit/Screens/<Name>Model.swift`:

   ```swift
   @MainActor @Observable
   public final class OverviewModel {
       public let resource = ScreenResource<API.OverviewPayload>()
       private let context: ScreenContext
       public init(context: ScreenContext) { self.context = context }
       public func load() async {
           await resource.load(Endpoints.getOverview(filters: context.filters.state), in: context)
       }
       // Derived display values (pure, testable) go here, not in the view.
   }
   ```
   Pushed screens take their id too (`Endpoints.getGame(gameId:)`,
   `getOpponent(opponentId:filters:)`).
2. **Tests** in `Tests/ChessDashboardKitTests/<Name>ModelTests.swift`: build a
   context with `makeEnvironment(...).context!` (or `ScreenContext` over a
   `FixtureAPIClient(directory: Repo.fixtures)`), call `load()`, assert values,
   the empty state (a variant fixture or `api.set(_:for:)`), and the offline
   cached state (`api.fail(with: .offline)` after one load).
3. **View** in `ChessDashboard/Screens/<Name>Screen.swift`:

   ```swift
   struct OverviewScreen: View {
       @Environment(AppEnvironment.self) private var env
       @State private var model: OverviewModel
       init(context: ScreenContext) { _model = State(initialValue: OverviewModel(context: context)) }
       var body: some View {
           ScreenState(resource: model.resource, retry: model.load) { payload in /* ... */ }
               .screenChrome(title: "Overview", page: .overview, resource: model.resource)
               .task(id: env.filters.state) { await model.load() }
               .refreshable { await model.load() }
       }
   }
   ```
   `.task(id: filters.state)` reloads when filters or the lens change;
   pull-to-refresh re-fetches and never Syncs.
4. **Wire it** in `App/MainTabView.swift` (or `MoreView`), replacing the
   `PlaceholderScreen` with `OverviewScreen(context: env.context!)` (the tabs
   only exist while signed in).

## Build and test

```bash
make kit-test            # swift test, on the Mac (seconds)
make ios-test            # same suite on a simulator (SIM_NAME="iPhone 17" by default)
make ios-build           # Debug build for a simulator
make ios-build-release   # Release build, generic simulator, no signing
make ios-codegen         # regenerate API types + theme after a spec/THEME change
```

Signing and TestFlight: `make ios-testflight` (see the README's iOS section).
CI runs `swift test` and the simulator tests in a macOS job when `ios/**` or
`openapi/**` change.
