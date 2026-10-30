import CryptoKit
import Foundation
import Testing
@testable import ChessDashboardKit

@Suite("Contract")
struct ContractTests {
	@Test("the generated types match openapi/v1.json")
	func generatedTypesAreCurrent() throws {
		let digest = SHA256.hash(data: try Data(contentsOf: Repo.spec))
			.map { String(format: "%02x", $0) }.joined()
		#expect(
			digest == API.specDigest,
			"openapi/v1.json changed: run .venv/bin/python ios/scripts/gen_api_types.py")
	}

	/// Every recorded fixture decodes through its operation's generated type.
	/// `<operationId>[.variant].json`; a new fixture is covered automatically.
	@Test("every recorded fixture decodes", arguments: try Repo.fixtureFiles())
	func fixtureDecodes(_ file: URL) throws {
		let operationId = String(file.lastPathComponent.split(separator: ".")[0])
		let type = try #require(API.responseTypes[operationId], "no operation \(operationId)")
		let data = try Data(contentsOf: file)
		if isErrorBody(data) {
			_ = try JSONDecoder().decode(API.ErrorResponse.self, from: data)
		} else {
			_ = try JSONDecoder().decode(type, from: data)
		}
	}

	@Test("the session and meta fixtures exist")
	func foundationFixturesExist() throws {
		let names = try Repo.fixtureFiles().map(\.lastPathComponent)
		#expect(names.contains("createSession.json"))
		#expect(names.contains("getMeta.json"))
	}

	private func isErrorBody(_ data: Data) -> Bool {
		guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			return false
		}
		return object.keys.sorted() == ["error"]
	}
}
