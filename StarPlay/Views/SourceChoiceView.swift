import SwiftUI

struct SourceChoiceView: View {
    let onUseDefault: () -> Void
    let onUseCustom:  () -> Void
    @EnvironmentObject var tm:    ThemeManager
    @EnvironmentObject var prefs: AppPreferences

    var isArabic: Bool { prefs.languageCode == "ar" }

    var body: some View {
        ZStack {
            tm.c.background.ignoresSafeArea()
            LinearGradient(
                colors: [tm.c.accentSoft.opacity(0.5), Color.clear],
                startPoint: .top, endPoint: .center
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                // Logo
                ZStack {
                    Circle().fill(tm.c.accentSoft).frame(width: 96, height: 96)
                    Circle().stroke(tm.c.accent.opacity(0.2), lineWidth: 1).frame(width: 96, height: 96)
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 44)).foregroundColor(tm.c.accent)
                }
                Spacer().frame(height: Sp.xl)
                Text(isArabic ? "اختر قائمة القنوات" : "Choose Your Playlist")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(tm.c.textPrimary)
                    .multilineTextAlignment(.center)
                Spacer().frame(height: Sp.sm)
                Text(isArabic
                     ? "استخدم القائمة الافتراضية أو حمّل قائمتك الخاصة"
                     : "Use the built-in list or load your own playlist")
                    .font(.system(size: 14))
                    .foregroundColor(tm.c.textSecondary)
                    .multilineTextAlignment(.center)
                Spacer().frame(height: 52)

                SourceRow(
                    icon: "checkmark.icloud.fill",
                    iconColor: tm.c.accent,
                    title:    isArabic ? "القائمة الافتراضية" : "Use Default Playlist",
                    subtitle: isArabic ? "قنوات مختارة، تتحدث تلقائياً" : "Curated channels, auto-updated from server",
                    accent: tm.c.accent,
                    action: onUseDefault
                )
                Spacer().frame(height: Sp.lg)
                SourceRow(
                    icon: "folder.badge.plus",
                    iconColor: tm.c.secondary,
                    title:    isArabic ? "قائمتي الخاصة" : "Load My Own Playlist",
                    subtitle: isArabic ? "أدخل رابطاً أو اختر ملفاً من جهازك" : "Enter a URL or pick a file from your device",
                    accent: tm.c.secondary,
                    action: onUseCustom
                )
                Spacer()
            }
            .padding(.horizontal, Sp.xl)
        }
    }
}

private struct SourceRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let accent: Color
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Sp.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: Sp.r_md)
                        .fill(iconColor.opacity(0.13))
                        .frame(width: 54, height: 54)
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(iconColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "808080"))
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(accent.opacity(0.6))
            }
            .padding(Sp.lg)
            .background(Color(hex: "111111"))
            .cornerRadius(Sp.r_xl)
            .overlay(RoundedRectangle(cornerRadius: Sp.r_xl).stroke(accent.opacity(0.22), lineWidth: 1))
        }
        .scaleEffect(pressed ? 0.98 : 1)
        .animation(.easeOut(duration: 0.1), value: pressed)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = true }
            .onEnded   { _ in pressed = false })
    }
}
