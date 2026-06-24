import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

enum MoneyFormatter {
    static func money(_ value: Double, signed: Bool = false) -> String {
        let sign: String
        if signed {
            sign = value > 0 ? "+" : value < 0 ? "-" : ""
        } else {
            sign = value < 0 ? "-" : ""
        }
        return "\(sign)¥ \(abs(value).formatted(.number.precision(.fractionLength(2))))"
    }

    static func plainMoney(_ value: Double) -> String {
        "¥ \(value.formatted(.number.precision(.fractionLength(2))))"
    }

    static func percent(_ value: Double, signed: Bool = false) -> String {
        let sign = signed && value > 0 ? "+" : ""
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(2))))%"
    }
}

enum FundCodeFormatter {
    static func display(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "--" }
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    }
}

enum ValueTone {
    static func color(for value: Double) -> Color {
        if value > 0 { return .red }
        if value < 0 { return .green }
        return .secondary
    }
}

extension Color {
    static let fundPulseGreen = Color(red: 75 / 255, green: 166 / 255, blue: 110 / 255)
}

#if canImport(AppKit)
extension NSColor {
    static let fundPulseGreen = NSColor(red: 75 / 255, green: 166 / 255, blue: 110 / 255, alpha: 1)
}
#endif
