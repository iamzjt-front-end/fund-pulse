import SwiftUI

enum PanelDesign {
    static let accent = Color(nsColor: .systemRed)
    static let panelBackground = Color(nsColor: panelBackgroundNSColor)
    static let cardBackground = Color(nsColor: .controlBackgroundColor).opacity(0.64)
    static let selectorBackground = Color(nsColor: .controlBackgroundColor).opacity(0.78)
    static let inputBackground = Color(nsColor: .textBackgroundColor).opacity(0.78)

    static let panelBackgroundNSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            return NSColor(red: 17 / 255, green: 19 / 255, blue: 24 / 255, alpha: 0.98)
        }
        return NSColor(red: 251 / 255, green: 249 / 255, blue: 245 / 255, alpha: 0.99)
    }

    static let panelChromeNSColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            return NSColor(red: 35 / 255, green: 39 / 255, blue: 46 / 255, alpha: 0.98)
        }
        return NSColor(red: 255 / 255, green: 251 / 255, blue: 242 / 255, alpha: 0.98)
    }

    static let panelChromeBackground = Color(nsColor: panelChromeNSColor)

    static func border(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color(nsColor: .separatorColor).opacity(0.42), lineWidth: 0.6)
    }
}

struct PanelHeader: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var tint: Color = PanelDesign.accent
    var accessoryText: String? = nil
    var accessoryColor: Color = .orange
    var actionSystemImage: String? = nil
    var actionTitle: String? = nil
    var actionBadgeText: String? = nil
    var actionHelp: String? = nil
    var onAction: (() -> Void)? = nil
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let accessoryText {
                Text(accessoryText)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .foregroundStyle(accessoryColor)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(accessoryColor.opacity(0.11), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(accessoryColor.opacity(0.18), lineWidth: 0.6)
                    )
            }

            Spacer()

            if let actionTitle, let onAction {
                Button {
                    onAction()
                } label: {
                    HStack(spacing: 5) {
                        if let actionSystemImage {
                            Image(systemName: actionSystemImage)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(actionTitle)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        if let actionBadgeText {
                            Text(actionBadgeText)
                                .font(.system(size: 9, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 64, minHeight: 26)
                    .background(PanelDesign.selectorBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(PanelDesign.border(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(actionHelp ?? actionTitle)
                .layoutPriority(2)
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("关闭")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
    }
}

struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelDesign.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(PanelDesign.border(cornerRadius: 10))
    }
}

struct PanelSegmentedPicker<Value: Hashable & Identifiable>: View {
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String
    var tint: Color = PanelDesign.accent

    var body: some View {
        HStack(spacing: 4) {
            ForEach(values) { value in
                Button {
                    selection = value
                } label: {
                    Text(title(value))
                        .font(.system(size: 11, weight: selection == value ? .semibold : .medium))
                        .foregroundStyle(selection == value ? tint : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(
                            selection == value ? Color(nsColor: .textBackgroundColor).opacity(0.92) : Color.clear,
                            in: Capsule()
                        )
                        .overlay {
                            if selection == value {
                                Capsule()
                                    .stroke(tint.opacity(0.18), lineWidth: 0.6)
                            }
                        }
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .padding(2)
        .background(PanelDesign.selectorBackground, in: Capsule())
    }
}

struct PanelTextInput: View {
    let placeholder: String
    @Binding var text: String
    var suffix: String?
    var isDisabled = false

    init(_ placeholder: String, text: Binding<String>, suffix: String? = nil, isDisabled: Bool = false) {
        self.placeholder = placeholder
        self._text = text
        self.suffix = suffix
        self.isDisabled = isDisabled
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .monospacedDigit()
                .disabled(isDisabled)

            if let suffix {
                Text(suffix)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(PanelDesign.inputBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(isDisabled ? 0.24 : 0.45), lineWidth: 0.6)
        )
        .opacity(isDisabled ? 0.68 : 1)
    }
}

struct PanelNativeDatePicker: NSViewRepresentable {
    @Binding var selection: Date
    var elements: NSDatePicker.ElementFlags
    var isEnabled = true

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.showPicker(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.image = NSImage(systemSymbolName: isTimeOnly ? "clock" : "calendar", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.setButtonType(.momentaryPushIn)
        context.coordinator.button = button
        context.coordinator.elements = elements
        context.coordinator.isTimeOnly = isTimeOnly
        context.coordinator.updateButtonTitle()
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.elements = elements
        context.coordinator.isTimeOnly = isTimeOnly
        context.coordinator.updateButtonTitle()
        button.isEnabled = isEnabled
        button.alphaValue = isEnabled ? 1 : 0.58
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection, elements: elements, isTimeOnly: isTimeOnly)
    }

    private var isTimeOnly: Bool {
        elements.contains(.hourMinute) && !elements.contains(.yearMonthDay)
    }

    final class Coordinator: NSObject {
        var selection: Binding<Date>
        var elements: NSDatePicker.ElementFlags
        var isTimeOnly: Bool
        weak var button: NSButton?
        private var popover: NSPopover?

        init(selection: Binding<Date>, elements: NSDatePicker.ElementFlags, isTimeOnly: Bool) {
            self.selection = selection
            self.elements = elements
            self.isTimeOnly = isTimeOnly
        }

        @MainActor
        @objc func showPicker(_ sender: NSButton) {
            if popover?.isShown == true {
                popover?.close()
                return
            }

            if !isTimeOnly {
                showCalendarPicker(relativeTo: sender)
                return
            }

            let picker = NSDatePicker()
            picker.datePickerStyle = .clockAndCalendar
            picker.datePickerElements = elements
            picker.dateValue = selection.wrappedValue
            picker.locale = Locale(identifier: "zh_CN")
            picker.calendar = Calendar.current
            picker.timeZone = TimeZone.current
            picker.controlSize = .regular
            picker.focusRingType = .none
            picker.target = self
            picker.action = #selector(valueChanged(_:))

            picker.sizeToFit()
            let pickerSize = picker.fittingSize
            let contentSize = NSSize(
                width: max(pickerSize.width + 16, isTimeOnly ? 136 : 206),
                height: max(pickerSize.height + 16, isTimeOnly ? 82 : 176)
            )
            let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
            picker.frame = NSRect(
                x: (contentSize.width - pickerSize.width) / 2,
                y: (contentSize.height - pickerSize.height) / 2,
                width: pickerSize.width,
                height: pickerSize.height
            )
            container.addSubview(picker)

            let controller = NSViewController()
            controller.view = container
            controller.preferredContentSize = contentSize

            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.contentSize = contentSize
            popover.contentViewController = controller
            self.popover = popover
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        }

        @MainActor
        private func showCalendarPicker(relativeTo sender: NSButton) {
            let contentSize = NSSize(width: 300, height: 336)
            let hostingView = NSHostingView(
                rootView: PanelCalendarPopoverContent(selectedDate: selection.wrappedValue) { [weak self] date in
                    guard let self else { return }
                    selection.wrappedValue = date
                    updateButtonTitle()
                    self.popover?.close()
                }
            )
            hostingView.frame = NSRect(origin: .zero, size: contentSize)

            let controller = NSViewController()
            controller.view = hostingView
            controller.preferredContentSize = contentSize

            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.contentSize = contentSize
            popover.contentViewController = controller
            self.popover = popover
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        }

        @MainActor
        @objc func valueChanged(_ sender: NSDatePicker) {
            selection.wrappedValue = sender.dateValue
            updateButtonTitle()
            if !isTimeOnly {
                popover?.close()
            }
        }

        @MainActor
        func updateButtonTitle() {
            button?.title = formatted(selection.wrappedValue)
        }

        private func formatted(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.calendar = Calendar.current
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = isTimeOnly ? "HH:mm" : "yyyy/M/d"
            return formatter.string(from: date)
        }
    }
}

struct PanelNativeTimePicker: NSViewRepresentable {
    @Binding var selection: Date
    var isEnabled = true

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.showPicker(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.contentTintColor = .systemBlue
        button.setButtonType(.momentaryPushIn)
        context.coordinator.button = button
        context.coordinator.updateButtonTitle()
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.selection = $selection
        context.coordinator.updateButtonTitle()
        button.isEnabled = isEnabled
        button.alphaValue = isEnabled ? 1 : 0.58
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class Coordinator: NSObject {
        var selection: Binding<Date>
        weak var button: NSButton?
        private var popover: NSPopover?

        init(selection: Binding<Date>) {
            self.selection = selection
        }

        @MainActor
        @objc func showPicker(_ sender: NSButton) {
            if popover?.isShown == true {
                popover?.close()
                return
            }

            let contentSize = NSSize(width: 268, height: 252)
            let hostingView = NSHostingView(
                rootView: PanelTimeWheelPopoverContent(selectedTime: selection.wrappedValue) { [weak self] date in
                    guard let self else { return }
                    selection.wrappedValue = date
                    updateButtonTitle()
                }
            )
            hostingView.frame = NSRect(origin: .zero, size: contentSize)

            let controller = NSViewController()
            controller.view = hostingView
            controller.preferredContentSize = contentSize

            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.contentSize = contentSize
            popover.contentViewController = controller
            self.popover = popover
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        }

        @MainActor
        func updateButtonTitle() {
            button?.title = formatted(selection.wrappedValue)
        }

        private func formatted(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.calendar = Calendar.current
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
    }
}

private struct PanelCalendarPopoverContent: View {
    let selectedDate: Date
    let onSelect: (Date) -> Void

    @State private var visibleMonth: Date

    private let calendar: Calendar
    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 6), count: 7)
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    init(selectedDate: Date, onSelect: @escaping (Date) -> Void) {
        self.selectedDate = selectedDate
        self.onSelect = onSelect
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = 2
        self.calendar = calendar
        _visibleMonth = State(initialValue: calendar.startOfMonth(for: selectedDate))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("日期")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text(selectedDateText)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: .systemBlue))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.82), in: Capsule())
            }
            .padding(.horizontal, 16)
            .frame(height: 56)

            Divider()
                .opacity(0.45)

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Button {
                        visibleMonth = calendar.startOfMonth(for: selectedDate)
                    } label: {
                        HStack(spacing: 5) {
                            Text(monthTitle)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)

                    Spacer()

                    calendarIconButton("chevron.left") {
                        moveMonth(-1)
                    }
                    calendarIconButton("chevron.right") {
                        moveMonth(1)
                    }
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(weekdays, id: \.self) { weekday in
                        Text(weekday)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 20)
                    }

                    ForEach(calendarDays) { day in
                        Button {
                            onSelect(day.date)
                        } label: {
                            Text("\(calendar.component(.day, from: day.date))")
                                .font(.system(size: 15, weight: isSelected(day.date) ? .semibold : .regular))
                                .monospacedDigit()
                                .foregroundStyle(dayForeground(day))
                                .frame(width: 34, height: 34)
                                .background(dayBackground(day), in: Circle())
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.56),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .padding(12)
        }
        .frame(width: 300, height: 336)
        .background(PanelDesign.panelBackground)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy年 M月"
        return formatter.string(from: visibleMonth)
    }

    private var selectedDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy/M/d"
        return formatter.string(from: selectedDate)
    }

    private var calendarDays: [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth),
              let firstGridDate = calendar.date(
                byAdding: .day,
                value: -weekdayOffset(from: monthInterval.start),
                to: monthInterval.start
              )
        else {
            return []
        }

        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstGridDate) else { return nil }
            return CalendarDay(
                date: date,
                isCurrentMonth: calendar.isDate(date, equalTo: visibleMonth, toGranularity: .month)
            )
        }
    }

    private func calendarIconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemBlue))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func weekdayOffset(from date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private func moveMonth(_ offset: Int) {
        visibleMonth = calendar.date(byAdding: .month, value: offset, to: visibleMonth) ?? visibleMonth
    }

    private func isSelected(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    private func dayForeground(_ day: CalendarDay) -> Color {
        if isSelected(day.date) { return Color(nsColor: .systemBlue) }
        if !day.isCurrentMonth { return Color.secondary.opacity(0.26) }
        if isToday(day.date) { return Color(nsColor: .systemBlue) }
        return .primary
    }

    private func dayBackground(_ day: CalendarDay) -> Color {
        if isSelected(day.date) {
            Color(nsColor: .systemBlue).opacity(0.18)
        } else if isToday(day.date) {
            Color(nsColor: .systemBlue).opacity(0.08)
        } else {
            Color.clear
        }
    }

    private struct CalendarDay: Identifiable {
        let date: Date
        let isCurrentMonth: Bool

        var id: TimeInterval { date.timeIntervalSince1970 }
    }
}

private struct PanelTimeWheelPopoverContent: View {
    let selectedTime: Date
    let onChange: (Date) -> Void

    @State private var hour: Int
    @State private var minute: Int

    private let calendar: Calendar
    private let rowHeight: CGFloat = 30
    private let wheelHeight: CGFloat = 150

    init(selectedTime: Date, onChange: @escaping (Date) -> Void) {
        self.selectedTime = selectedTime
        self.onChange = onChange
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        self.calendar = calendar
        _hour = State(initialValue: calendar.component(.hour, from: selectedTime))
        _minute = State(initialValue: calendar.component(.minute, from: selectedTime))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("时间")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text(timeText(hour: hour, minute: minute))
                    .font(.system(size: 14, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: .systemBlue))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.82), in: Capsule())
            }
            .padding(.horizontal, 16)
            .frame(height: 56)

            Divider()
                .opacity(0.45)

            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.70))
                    .frame(height: 34)

                HStack(spacing: 18) {
                    wheelColumn(values: Array(0...23), selection: $hour, label: "时")
                    wheelColumn(values: Array(0...59), selection: $minute, label: "分")
                }
            }
            .frame(height: wheelHeight)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(width: 268, height: 252)
        .background(PanelDesign.panelBackground)
        .onChange(of: hour) { _, _ in
            emitChange()
        }
        .onChange(of: minute) { _, _ in
            emitChange()
        }
    }

    private func wheelColumn(values: [Int], selection: Binding<Int>, label: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: (wheelHeight - rowHeight) / 2)
                    ForEach(values, id: \.self) { value in
                        Button {
                            withAnimation(.easeOut(duration: 0.12)) {
                                selection.wrappedValue = value
                                proxy.scrollTo(value, anchor: .center)
                            }
                        } label: {
                            Text(String(format: "%02d", value))
                                .font(.system(size: 15, weight: value == selection.wrappedValue ? .semibold : .regular))
                                .monospacedDigit()
                                .foregroundStyle(wheelForeground(value: value, selected: selection.wrappedValue))
                                .frame(width: 58, height: rowHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .id(value)
                    }
                    Spacer()
                        .frame(height: (wheelHeight - rowHeight) / 2)
                }
            }
            .frame(width: 58, height: wheelHeight)
            .overlay(alignment: .trailing) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .offset(x: 14)
                    .allowsHitTesting(false)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.24),
                        .init(color: .black, location: 0.76),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo(selection.wrappedValue, anchor: .center)
                }
            }
        }
    }

    private func wheelForeground(value: Int, selected: Int) -> Color {
        let distance = abs(value - selected)
        if distance == 0 { return .primary }
        if distance == 1 { return Color.secondary.opacity(0.62) }
        if distance == 2 { return Color.secondary.opacity(0.36) }
        return Color.secondary.opacity(0.20)
    }

    private func emitChange() {
        var components = calendar.dateComponents([.year, .month, .day], from: selectedTime)
        components.hour = hour
        components.minute = minute
        components.second = 0
        if let date = calendar.date(from: components) {
            onChange(date)
        }
    }

    private func timeText(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        guard let interval = dateInterval(of: .month, for: date) else { return startOfDay(for: date) }
        return interval.start
    }
}

struct PanelButtonLabel: View {
    enum Style {
        case primary
        case secondary
        case destructive
    }

    let title: String
    var systemImage: String?
    var style: Style = .secondary
    var tint: Color = PanelDesign.accent
    var isEnabled = true

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 12, weight: style == .primary ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            if style != .primary {
                PanelDesign.border(cornerRadius: 9)
            }
        }
        .contentShape(Rectangle())
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            isEnabled ? .white : .secondary
        case .secondary:
            .primary
        case .destructive:
            .red
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            isEnabled ? tint : Color(nsColor: .controlBackgroundColor).opacity(0.78)
        case .secondary, .destructive:
            PanelDesign.cardBackground
        }
    }
}
