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

enum StatusBarTone {
    enum Intensity: Equatable {
        case neutral
        case subtle
        case normal
        case clear
        case strong
        case extreme
    }

    static func intensity(forRate rate: Double) -> Intensity {
        let magnitude = abs(rate)
        if magnitude <= 0.10 { return .neutral }
        if magnitude < 1.00 { return .subtle }
        if magnitude < 2.00 { return .normal }
        if magnitude < 3.00 { return .clear }
        if magnitude < 4.00 { return .strong }
        return .extreme
    }
}

extension Color {
    static let fundPulseGreen = Color(red: 75 / 255, green: 166 / 255, blue: 110 / 255)
}

#if canImport(AppKit)
extension NSColor {
    static let fundPulseGreen = NSColor(red: 75 / 255, green: 166 / 255, blue: 110 / 255, alpha: 1)
}

extension StatusBarTone {
    static func menuBarColor(forRate rate: Double) -> NSColor {
        let palette: [Intensity: (red: CGFloat, green: CGFloat, blue: CGFloat)] = rate > 0
            ? [
                .neutral: (142, 142, 147),
                .subtle: (255, 138, 128),
                .normal: (255, 90, 106),
                .clear: (230, 59, 74),
                .strong: (185, 21, 42),
                .extreme: (110, 7, 20)
            ]
            : [
                .neutral: (142, 142, 147),
                .subtle: (123, 216, 143),
                .normal: (75, 166, 110),
                .clear: (46, 139, 87),
                .strong: (20, 107, 58),
                .extreme: (7, 59, 36)
            ]
        let color = palette[intensity(forRate: rate)] ?? (142, 142, 147)
        return NSColor(red: color.red / 255, green: color.green / 255, blue: color.blue / 255, alpha: 1)
    }
}
#endif
