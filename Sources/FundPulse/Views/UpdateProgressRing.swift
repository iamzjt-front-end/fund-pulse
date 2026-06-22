import SwiftUI

struct UpdateProgressRing: View {
    var progress: Double
    var tint: Color = .orange
    var lineWidth: CGFloat = 3.2
    var showsGlyph = true

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.16))

            Circle()
                .stroke(tint.opacity(0.26), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if showsGlyph {
                Image(systemName: "arrow.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        .padding(lineWidth / 2)
        .animation(.easeOut(duration: 0.16), value: clampedProgress)
        .shadow(color: tint.opacity(0.24), radius: 4, x: 0, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("下载进度")
        .accessibilityValue("\(Int(clampedProgress * 100))%")
    }
}
