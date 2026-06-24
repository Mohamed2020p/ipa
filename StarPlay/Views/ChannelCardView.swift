import SwiftUI

struct ChannelCardView: View {
    let channel: Channel
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void

    @EnvironmentObject var tm: ThemeManager
    @State private var pressed = false
    @State private var pulse   = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // --- Background ---
            ZStack {
                tm.c.surfaceCard
                if !channel.logo.isEmpty, let url = URL(string: channel.logo) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        default:
                            fallbackBG
                        }
                    }
                } else { fallbackBG }
            }

            // --- Gradient vignette ---
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )

            // --- Bottom info ---
            VStack(alignment: .leading, spacing: 3) {
                Text(channel.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(channel.category)
                    .font(.system(size: 11))
                    .foregroundColor(tm.c.accent)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)

            // --- Top badges ---
            VStack {
                HStack {
                    // Channel number
                    Text(String(format: "%03d", index + 1))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(tm.c.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())

                    Spacer()

                    // LIVE badge
                    if isSelected {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(tm.c.live.opacity(pulse ? 1 : 0.3))
                                .frame(width: 6, height: 6)
                                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                                .onAppear { pulse = true }
                                .onDisappear { pulse = false }
                            Text("LIVE")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(tm.c.live)
                                .tracking(0.5)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.6))
                        .overlay(Capsule().stroke(tm.c.live.opacity(0.4), lineWidth: 0.5))
                        .clipShape(Capsule())
                    }
                }
                .padding(10)
                Spacer()
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Sp.r_xl))
        .overlay(
            RoundedRectangle(cornerRadius: Sp.r_xl)
                .stroke(isSelected ? tm.c.accent : tm.c.border,
                        lineWidth: isSelected ? 2 : 0.5)
        )
        .shadow(color: isSelected ? tm.c.accentGlow.opacity(0.6) : Color.black.opacity(0.4),
                radius: isSelected ? 14 : 4, x: 0, y: 4)
        .scaleEffect(pressed ? 0.96 : 1)
        .animation(.easeOut(duration: 0.12), value: pressed)
        .onTapGesture { onTap() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded   { _ in pressed = false }
        )
    }

    private var fallbackBG: some View {
        ZStack {
            tm.c.surfaceCard
            VStack(spacing: 6) {
                Image(systemName: "tv.fill")
                    .font(.system(size: 28))
                    .foregroundColor(isSelected ? tm.c.accent : tm.c.textMuted)
                Text(String(channel.name.prefix(1)).uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(tm.c.textMuted)
            }
        }
    }
}
