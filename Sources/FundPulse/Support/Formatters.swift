import Foundation
import SwiftUI

#if canImport(AppKit)
import AppKit
#endif

enum MoneyFormatter {
    static func money(_ value: Double, signed: Bool = false) -> String {
        let value = normalizedZero(value)
        let sign: String
        if signed {
            sign = value > 0 ? "+" : value < 0 ? "-" : ""
        } else {
            sign = value < 0 ? "-" : ""
        }
        return "\(sign)¥ \(abs(value).formatted(.number.precision(.fractionLength(2))))"
    }

    static func plainMoney(_ value: Double) -> String {
        let value = normalizedZero(value)
        return "¥ \(value.formatted(.number.precision(.fractionLength(2))))"
    }

    static func percent(_ value: Double, signed: Bool = false) -> String {
        let sign = signed && value > 0 ? "+" : ""
        return "\(sign)\(value.formatted(.number.precision(.fractionLength(2))))%"
    }

    private static func normalizedZero(_ value: Double) -> Double {
        abs(value) < 0.005 ? 0 : value
    }
}

enum MenuBarStatusFormatter {
    static func text(amount: Double, rate: Double, mode: MenuBarContentMode) -> String {
        switch mode {
        case .amount:
            signedAmount(amount)
        case .rate:
            MoneyFormatter.percent(rate, signed: true)
        case .both:
            "\(signedAmount(amount)) | \(MoneyFormatter.percent(rate, signed: true))"
        }
    }

    private static func signedAmount(_ value: Double) -> String {
        let sign = value > 0 ? "+" : value < 0 ? "-" : ""
        return "\(sign)\(abs(value).formatted(.number.precision(.fractionLength(2))))"
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
        case maximum
    }

    static func intensity(forRate rate: Double) -> Intensity {
        let magnitude = abs(rate)
        if magnitude <= 0.10 { return .neutral }
        if magnitude < 1.00 { return .subtle }
        if magnitude < 2.00 { return .normal }
        if magnitude < 3.00 { return .clear }
        if magnitude < 4.00 { return .strong }
        if magnitude <= 5.00 { return .extreme }
        return .maximum
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
                .subtle: (255, 159, 154),
                .normal: (225, 130, 125),
                .clear: (196, 101, 98),
                .strong: (167, 72, 71),
                .extreme: (138, 43, 45),
                .maximum: (110, 7, 20)
            ]
            : [
                .neutral: (142, 142, 147),
                .subtle: (142, 221, 162),
                .normal: (114, 186, 135),
                .clear: (87, 152, 108),
                .strong: (60, 119, 83),
                .extreme: (35, 88, 59),
                .maximum: (7, 59, 36)
            ]
        let color = palette[intensity(forRate: rate)] ?? (142, 142, 147)
        return NSColor(red: color.red / 255, green: color.green / 255, blue: color.blue / 255, alpha: 1)
    }
}
#endif
