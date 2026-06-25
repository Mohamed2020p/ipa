import SwiftUI
import AVFoundation
import MobileVLCKit

// MARK: - Stream State
enum StreamState: Equatable {
    case idle
    case loading
    case buffering
    case playing
    case reconnecting(Int)
    case error(String)
}

// MARK: - VLC Stream Player
final class StreamPlayer: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    @Published var state: StreamState = .idle

    let vlcPlayer: VLCMediaPlayer = {
        let p = VLCMediaPlayer()
        return p
    }()

    let renderView: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.contentMode     = .scaleAspectFit
        return v
    }()

    private var currentURL:       URL?
    private var reconnectAttempts = 0
    private var reconnectTask:    Task<Void, Never>?
    private var watchdogTask:     Task<Void, Never>?

    override init() {
        super.init()
        vlcPlayer.delegate = self
        vlcPlayer.drawable = renderView
        vlcPlayer.scaleFactor = 0
        // Audio session is handled globally by AppDelegate
    }

    // MARK: - Public API
    func play(urlString: String) {
        cancelTasks()
        reconnectAttempts = 0

        let cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleaned) else {
            DispatchQueue.main.async { self.state = .error("Invalid URL") }
            return
        }
        currentURL = url
        DispatchQueue.main.async { self.state = .loading }
        doLoad(url: url)
    }

    func retry() {
        guard let url = currentURL else { return }
        cancelTasks()
        reconnectAttempts = 0
        DispatchQueue.main.async { self.state = .loading }
        doLoad(url: url)
    }

    func stop() {
        cancelTasks()
        vlcPlayer.stop()
        DispatchQueue.main.async { self.state = .idle }
    }

    private func cancelTasks() {
        reconnectTask?.cancel()
        watchdogTask?.cancel()
    }

    // MARK: - Core Load
    private func doLoad(url: URL) {
        let media = VLCMedia(url: url)
        media.addOption("--network-caching=2000")
        media.addOption("--clock-jitter=0")
        media.addOption("--clock-synchro=0")
        media.addOption("--http-reconnect")
        media.addOption("--http-continuous")
        media.addOption(":http-user-agent=VLC/3.0.18 LibVLC/3.0.18")
        media.addOption("--avcodec-hw=any")
        media.addOption("--ts-seek-percent")

        vlcPlayer.media = media
        vlcPlayer.play()

        watchdogTask?.cancel()
        watchdogTask = Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self.state == .loading || self.state == .buffering {
                    self.scheduleReconnect()
                }
            }
        }
    }

    // MARK: - VLCMediaPlayerDelegate
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        let s = vlcPlayer.state
        DispatchQueue.main.async {
            switch s {
            case .playing:
                self.cancelTasks()
                self.reconnectAttempts = 0
                self.state = .playing

            case .buffering:
                if self.state == .loading || self.state == .reconnecting(self.reconnectAttempts) {
                    self.state = .buffering
                }

            case .stopped, .ended:
                self.scheduleReconnect(delay: 2)

            case .error:
                self.scheduleReconnect()

            case .paused:
                self.vlcPlayer.play()

            case .opening:
                if self.state == .idle { self.state = .loading }

            default:
                break
            }
        }
    }

    // MARK: - Reconnect
    private func scheduleReconnect(delay overrideDelay: Double? = nil) {
        cancelTasks()
        reconnectAttempts += 1

        if reconnectAttempts > 15 {
            DispatchQueue.main.async {
                self.state = .error("Stream unavailable after \(self.reconnectAttempts) attempts.\nتعذّر الاتصال بالخادم.")
            }
            return
        }

        let wait = overrideDelay ?? min(Double(reconnectAttempts) * 2.0, 12.0)
        DispatchQueue.main.async { self.state = .reconnecting(self.reconnectAttempts) }

        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled, let url = self.currentURL else { return }
            await MainActor.run { self.doLoad(url: url) }
        }
    }

    deinit { stop() }
}

// MARK: - VLC UIView wrapper
struct VLCPlayerView: UIViewRepresentable {
    let renderView: UIView

    func makeUIView(context: Context) -> UIView {
        renderView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return renderView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Full-screen container UIViewController
final class FullscreenPlayerVC: UIViewController {
    var renderView: UIView?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var shouldAutorotate: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let rv = renderView else { return }
        rv.frame = view.bounds
        rv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(rv)
    }
}

// MARK: - Channel Player Widget
struct ChannelPlayerWidget: View {
    let channel:      Channel
    @Binding var isFullScreen: Bool
    @EnvironmentObject var tm: ThemeManager

    @StateObject private var sp          = StreamPlayer()
    @State private var pulseLive         = false
    @State private var showOverlay       = true
    @State private var overlayTimer: Task<Void, Never>? = nil
    @State private var showFullscreenModal = false

    var body: some View {
        ZStack {
            Color.black

            VLCPlayerView(renderView: sp.renderView)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleOverlay() }

            if showOverlay {
                VStack {
                    HStack {
                        HStack(spacing: 6) {
                            if case .playing = sp.state {
                                Circle()
                                    .fill(tm.c.live.opacity(pulseLive ? 1 : 0.35))
                                    .frame(width: 8, height: 8)
                                    .animation(
                                        .easeInOut(duration: 0.75)
                                            .repeatForever(autoreverses: true),
                                        value: pulseLive
                                    )
                                    .onAppear    { pulseLive = true  }
                                    .onDisappear { pulseLive = false }
                            }
                            Text(channel.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        Spacer()

                        Button(action: { enterFullscreen() }) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(tm.c.accent)
                                .frame(width: 36, height: 36)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.7), Color.clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    Spacer()
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: showOverlay)
            }

            stateOverlay
        }
        .frame(height: 230)
        .clipped()
        .onAppear    { sp.play(urlString: channel.url) }
        .onChange(of: channel) { sp.play(urlString: $0.url) }
        .onDisappear { sp.stop() }
        .fullScreenCover(isPresented: $showFullscreenModal) {
            FullscreenView(sp: sp, channel: channel, isPresented: $showFullscreenModal)
                .environmentObject(tm)
        }
    }

    private func enterFullscreen() {
        isFullScreen = true
        showFullscreenModal = true
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch sp.state {
        case .idle:
            EmptyView()

        case .loading:
            ZStack {
                Color.black.opacity(0.5)
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: tm.c.accent))
                        .scaleEffect(1.3)
                    Text("جاري التحميل…")
                        .font(.system(size: 13)).foregroundColor(.white)
                }
            }

        case .buffering:
            ZStack {
                Color.black.opacity(0.35)
                VStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: tm.c.accent))
                        .scaleEffect(1.2)
                    Text("Buffering…")
                        .font(.system(size: 12)).foregroundColor(.white)
                }
            }

        case .reconnecting(let n):
            ZStack {
                Color.black.opacity(0.55)
                VStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: tm.c.secondary))
                        .scaleEffect(1.2)
                    Text("Reconnecting… (\(n))")
                        .font(.system(size: 12)).foregroundColor(.white)
                    Text("جاري إعادة الاتصال…")
                        .font(.system(size: 11)).foregroundColor(tm.c.secondary.opacity(0.8))
                }
            }

        case .error(let msg):
            ZStack {
                Color.black.opacity(0.85)
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36)).foregroundColor(tm.c.error)
                    Text("Playback Failed")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                    Text("تعذّر تشغيل القناة")
                        .font(.system(size: 13)).foregroundColor(tm.c.error.opacity(0.8))
                    Text(msg.isEmpty ? "Stream may be offline." : msg)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "A0A0A0"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button(action: { sp.retry() }) {
                        Label("Retry / إعادة المحاولة", systemImage: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(tm.c.background)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(tm.c.accent)
                            .cornerRadius(10)
                    }
                }
                .padding()
            }

        case .playing:
            EmptyView()
        }
    }

    private func toggleOverlay() {
        overlayTimer?.cancel()
        withAnimation { showOverlay.toggle() }
        if showOverlay { startOverlayTimer() }
    }

    private func startOverlayTimer() {
        overlayTimer?.cancel()
        overlayTimer = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { showOverlay = false } }
        }
    }
}

// MARK: - Fullscreen Modal View
struct FullscreenView: View {
    @ObservedObject var sp: StreamPlayer
    let channel: Channel
    @Binding var isPresented: Bool
    @EnvironmentObject var tm: ThemeManager

    @State private var showControls  = true
    @State private var pulseLive     = false
    @State private var controlTimer: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VLCPlayerView(renderView: sp.renderView)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { toggleControls() }

            if showControls {
                VStack {
                    HStack {
                        Button(action: { exitFullscreen() }) {
                            Image(systemName: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Circle())
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            if case .playing = sp.state {
                                Circle()
                                    .fill(tm.c.live.opacity(pulseLive ? 1 : 0.3))
                                    .frame(width: 8, height: 8)
                                    .animation(
                                        .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                                        value: pulseLive
                                    )
                                    .onAppear    { pulseLive = true  }
                                    .onDisappear { pulseLive = false }
                            }
                            Text(channel.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        Spacer()

                        Button(action: { sp.retry() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.7), Color.clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                    Spacer()
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: showControls)
            }

            fullscreenStateOverlay
        }
        .onAppear {
            forceOrientation(.landscapeRight)
            startControlTimer()
        }
        .onDisappear {
            forceOrientation(.portrait)
        }
    }

    private func forceOrientation(_ orientation: UIInterfaceOrientation) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let mask: UIInterfaceOrientationMask = orientation == .portrait ? .portrait : .landscape
        AppDelegate.orientationLock = mask
        let pref = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
        scene.requestGeometryUpdate(pref) { _ in }
        scene.windows.forEach {
            $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    private func exitFullscreen() {
        controlTimer?.cancel()
        isPresented = false
    }

    private func toggleControls() {
        controlTimer?.cancel()
        withAnimation { showControls.toggle() }
        if showControls { startControlTimer() }
    }

    private func startControlTimer() {
        controlTimer?.cancel()
        controlTimer = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { showControls = false } }
        }
    }

    @ViewBuilder
    private var fullscreenStateOverlay: some View {
        switch sp.state {
        case .loading:
            ZStack {
                Color.black.opacity(0.45)
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: tm.c.accent))
                        .scaleEffect(1.5)
                    Text("جاري التحميل…")
                        .font(.system(size: 15)).foregroundColor(.white)
                }
            }
        case .buffering:
            ZStack {
                Color.black.opacity(0.35)
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: tm.c.accent))
                    .scaleEffect(1.4)
            }
        case .reconnecting(let n):
            ZStack {
                Color.black.opacity(0.55)
                VStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: tm.c.secondary))
                        .scaleEffect(1.4)
                    Text("Reconnecting… (\(n))")
                        .font(.system(size: 14)).foregroundColor(.white)
                }
            }
        case .error(let msg):
            ZStack {
                Color.black.opacity(0.85)
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44)).foregroundColor(tm.c.error)
                    Text("تعذّر تشغيل القناة")
                        .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                    Text(msg).font(.system(size: 13))
                        .foregroundColor(Color(hex: "A0A0A0"))
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                    Button(action: { sp.retry() }) {
                        Label("إعادة المحاولة", systemImage: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(tm.c.background)
                            .padding(.horizontal, 24).padding(.vertical, 12)
                            .background(tm.c.accent).cornerRadius(12)
                    }
                }
            }
        default:
            EmptyView()
        }
    }
}

// MARK: - Player Placeholder
struct PlayerPlaceholder: View {
    @EnvironmentObject var tm: ThemeManager
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 12) {
                Image(systemName: "play.tv.fill")
                    .font(.system(size: 40))
                    .foregroundColor(tm.c.accent.opacity(0.5))
                Text("اختر قناة للمشاهدة")
                    .font(.system(size: 14)).foregroundColor(tm.c.textMuted)
                Text("Select a channel to watch")
                    .font(.system(size: 12)).foregroundColor(tm.c.textMuted.opacity(0.6))
            }
        }
        .frame(height: 230)
    }
}
