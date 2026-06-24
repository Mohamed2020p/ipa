import SwiftUI

// MARK: - Layout constants
enum Sp {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let xl2: CGFloat = 32
    static let xl3: CGFloat = 48
    static let r_sm:  CGFloat = 8
    static let r_md:  CGFloat = 12
    static let r_lg:  CGFloat = 16
    static let r_xl:  CGFloat = 20
    static let r_pill: CGFloat = 50
}

// MARK: - Animated Signal Bars
struct SignalBars: View {
    var color: Color = .cyan
    var animated: Bool = true
    var count: Int = 4
    @State private var phases: [Double]

    init(color: Color = .cyan, animated: Bool = true, count: Int = 4) {
        self.color    = color
        self.animated = animated
        self.count    = count
        _phases = State(initialValue: (0..<count).map { 0.35 + Double($0) * 0.2 })
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3, height: 16 * phases[i])
                    .animation(
                        animated
                        ? .easeInOut(duration: 0.5 + Double(i) * 0.1)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.12)
                        : .none,
                        value: phases[i]
                    )
            }
        }
        .onAppear {
            guard animated else { return }
            for i in 0..<count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                    phases[i] = i % 2 == 0 ? 1.0 : 0.3
                }
            }
        }
    }
}

// MARK: - Glass Card modifier
struct GlassCard: ViewModifier {
    let bg: Color
    let border: Color
    let radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(bg)
            .cornerRadius(radius)
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(border, lineWidth: 0.5))
    }
}
extension View {
    func glassCard(bg: Color, border: Color, radius: CGFloat = Sp.r_lg) -> some View {
        modifier(GlassCard(bg: bg, border: border, radius: radius))
    }
}

// MARK: - Primary Button
struct SPButton: View {
    let title: String
    var accent: Color
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(enabled ? .black : Color(hex: "505050"))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(enabled ? accent : Color(hex: "1C1C1C"))
                .cornerRadius(Sp.r_md)
        }
        .disabled(!enabled)
    }
}

// MARK: - SP Text Field
struct SPTextField: View {
    @Binding var text: String
    let placeholder: String
    var isError: Bool = false
    var errorText: String? = nil
    var accent: Color = Color(hex: "00D4FF")
    var leadingIcon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Sp.sm) {
                if let icon = leadingIcon {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundColor(isError ? Color(hex: "FF4444") : accent.opacity(0.7))
                        .frame(width: 20)
                }
                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 15))
                            .foregroundColor(Color(hex: "505050"))
                    }
                    TextField("", text: $text)
                        .foregroundColor(.white)
                        .font(.system(size: 15))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .padding(.horizontal, Sp.md)
            .frame(height: 54)
            .background(Color(hex: "111111"))
            .cornerRadius(Sp.r_md)
            .overlay(
                RoundedRectangle(cornerRadius: Sp.r_md)
                    .stroke(isError ? Color(hex: "FF4444") : (text.isEmpty ? Color(hex: "1C1C1C") : accent.opacity(0.5)), lineWidth: 1)
            )
            if isError, let err = errorText {
                Label(err, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "FF4444"))
            }
        }
    }
}

// MARK: - Loading Screen
struct SPLoadingView: View {
    let message: String
    var subMessage: String = ""
    var accent: Color = Color(hex: "00D4FF")

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: Sp.xl) {
                ZStack {
                    Circle()
                        .stroke(accent.opacity(0.15), lineWidth: 3)
                        .frame(width: 64, height: 64)
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                        .modifier(SpinModifier())
                }
                VStack(spacing: Sp.sm) {
                    Text(message)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    if !subMessage.isEmpty {
                        Text(subMessage)
                            .font(.system(size: 14))
                            .foregroundColor(accent)
                    }
                }
            }
        }
    }
}

struct SpinModifier: ViewModifier {
    @State private var angle: Double = 0
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .onAppear { withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { angle = 360 } }
    }
}
