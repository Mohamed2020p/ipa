import SwiftUI

struct LanguageSelectionView: View {
    let onLanguageSelected: (String) -> Void
    @EnvironmentObject var tm: ThemeManager

    var body: some View {
        ZStack {
            tm.c.background.ignoresSafeArea()
            tm.c.heroGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                // Icon
                ZStack {
                    Circle().fill(tm.c.accentSoft).frame(width: 90, height: 90)
                    Circle().stroke(tm.c.accent.opacity(0.25), lineWidth: 1).frame(width: 90, height: 90)
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 40))
                        .foregroundColor(tm.c.accent)
                }

                Spacer().frame(height: Sp.xl)

                Text("Select Language")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(tm.c.textPrimary)
                Text("اختر اللغة")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(tm.c.textSecondary)
                    .padding(.top, 4)

                Spacer().frame(height: 52)

                LangCard(flag: "🇺🇸", label: "English", sublabel: "Continue in English",
                         accent: tm.c.accent) { onLanguageSelected("en") }

                Spacer().frame(height: Sp.lg)

                LangCard(flag: "🇸🇦", label: "العربية", sublabel: "المتابعة بالعربية",
                         accent: tm.c.secondary) { onLanguageSelected("ar") }

                Spacer()
            }
            .padding(.horizontal, Sp.xl)
        }
    }
}

private struct LangCard: View {
    let flag: String
    let label: String
    let sublabel: String
    let accent: Color
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Sp.lg) {
                Text(flag).font(.system(size: 32))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    Text(sublabel)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "808080"))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(accent)
            }
            .padding(.horizontal, Sp.xl)
            .padding(.vertical, Sp.lg)
            .background(Color(hex: "111111"))
            .cornerRadius(Sp.r_xl)
            .overlay(
                RoundedRectangle(cornerRadius: Sp.r_xl)
                    .stroke(accent.opacity(0.3), lineWidth: 1)
            )
        }
        .scaleEffect(pressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.1), value: pressed)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = true }
            .onEnded   { _ in pressed = false })
    }
}
