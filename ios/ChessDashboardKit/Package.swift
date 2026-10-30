// swift-tools-version: 6.2
import PackageDescription

// Everything testable in the app: the generated API types, the client, the
// session, filter, and cache stores, and every screen's view model. One
// dependency: ChessKit, for chess rules only (SAN to moves, positions). The
// PGN move tree is ours (Board/PGNTree.swift); ChessKit's own PGN parser
// rejects comments before move 1 and loses moves in nested variations.
// Everything else (Foundation, Security, Observation, CryptoKit, Testing)
// ships with the toolchain.
//
// macOS is listed only so `swift test` runs the suite in seconds. Nothing here
// imports UIKit; views live in the app target. The tests read the server's
// recorded fixtures straight from ../../openapi/fixtures (see Fixtures.swift),
// so a fixture a server ticket records is covered with no copy step.
let package = Package(
	name: "ChessDashboardKit",
	platforms: [.iOS(.v18), .macOS(.v15)],
	products: [.library(name: "ChessDashboardKit", targets: ["ChessDashboardKit"])],
	dependencies: [
		.package(url: "https://github.com/chesskit-app/chesskit-swift", exact: "0.17.0")
	],
	targets: [
		.target(
			name: "ChessDashboardKit",
			dependencies: [.product(name: "ChessKit", package: "chesskit-swift")],
			swiftSettings: [.swiftLanguageMode(.v6)]
		),
		.testTarget(
			name: "ChessDashboardKitTests",
			dependencies: ["ChessDashboardKit"],
			swiftSettings: [.swiftLanguageMode(.v6)]
		),
	]
)
