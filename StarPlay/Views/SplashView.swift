import SwiftUI

struct SplashView: View {
    let onTimeout: () -> Void
    @EnvironmentObject var tm: ThemeManager
    @State private var opacity: Double = 0
    @State private var scale:   Double = 0.85
    @State private var glowScale: Double = 0.6

    var body: some View {
        ZStack {
            tm.c.background.ignoresSafeArea()
            RadialGradient(
                colors: [tm.c.accentGlow.opacity(0.35), Color.clear],
                center: .center, startRadius: 0, endRadius: 320
            )
            .ignoresSafeArea()
            .scaleEffect(glowScale)

            VStack(spacing: 0) {
                Spacer()
                // Icon ring
                ZStack {
                    Circle()
                        .fill(tm.c.accentSoft)
                        .frame(width: 110, height: 110)
                    Circle()
                        .stroke(tm.c.accent.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 110, height: 110)
                    Circle()
                        .stroke(tm.c.accent.opacity(0.08), lineWidth: 12)
                        .frame(width: 130, height: 130)
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundColor(tm.c.accent)
                }
                .scaleEffect(scale)

                Spacer().frame(height: 32)

                Text("STARPLAY")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(tm.c.textPrimary)
                    .tracking(4)

                Spacer().frame(height: 8)

                Text("Premium IPTV Experience")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(tm.c.textMuted)
                    .tracking(1)

                Spacer().frame(height: 28)

                SignalBars(color: tm.c.accent, animated: true, count: 5)

                Spacer()

                Text("by c0derz")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(tm.c.textMuted)
                    .padding(.bottom, 36)
            }
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                scale      = 1.0
                glowScale  = 1.0
            }
            withAnimation(.easeIn(duration: 0.6)) { opacity = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { onTimeout() }
        }
    }
}
