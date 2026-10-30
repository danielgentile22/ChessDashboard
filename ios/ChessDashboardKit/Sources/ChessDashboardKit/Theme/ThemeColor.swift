import SwiftUI

/// One theme color as the web writes it: 0-255 channels plus an alpha.
/// `Theme` (generated from `styles.THEME`) holds every token; use
/// `Theme.win.color` in a view.
public struct ThemeColor: Sendable, Hashable {
	public let red: Int
	public let green: Int
	public let blue: Int
	public let alpha: Double

	public init(red: Int, green: Int, blue: Int, alpha: Double) {
		self.red = red
		self.green = green
		self.blue = blue
		self.alpha = alpha
	}

	public var color: Color {
		Color(
			.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255,
			opacity: alpha)
	}
}
