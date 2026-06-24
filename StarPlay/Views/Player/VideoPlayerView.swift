import SwiftUI
import AVKit
import AVFoundation

// MARK: - Stream State
enum StreamState: Equatable {
    case loading
    case buffering
    case playing
    case reconnecting(Int)
    case error(String)
}

// MARK: - Stream Player ViewModel
final class StreamPlayer: ObservableObject {
    @Published var state: StreamState = .loading

    // Single persistent player — never recreated
    let player: AVPlayer = {
        let p = AVPlayer()
        p.automaticallyWaitsToMinimizeStalling = true
        return p
    }()

    private var currentURL: URL?
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var statusObserver:  NSKeyValueObservation?
    private var rateObserver:    NSKeyValueObservation?
    private var tcObserver:      NSKeyValueObservation?

    init() { activateAudioSession() }

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .moviePlayback,
            options: [.allowBluetooth, .allowAirPlay]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Public API
    func play(urlString: String) {
        reconnectTask?.cancel()
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
        reconnectTask?.cancel()
        reconnectAttempts = 0
        DispatchQueue.main.async { self.state = .loading }
        doLoad(url: url)
    }

    func stop() {
        reconnectTask?.cancel()
        statusObserver?.invalidate()
        rateObserver?.invalidate()
        tcObserver?.invalidate()
        NotificationCenter.default.removeObserver(self)
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: - Core load
    private func doLoad(url: URL) {
        // VLC user-agent is accepted by ~99% of IPTV servers.
        // "Lavf/58.76.100" (FFmpeg) is the fallback most panels also accept.
        let headers: [String: String] = [
            "User-Agent":  "VLC/3.0.18 LibVLC/3.0.18",
            "Accept":      "*/*",
            "Connection":  "keep-alive",
            "Icy-MetaData":"0"
        ]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])

        let item = AVPlayerItem(asset: asset)
        // Lower buffer so live TV starts fast and re-syncs quickly after reconnect
        item.preferredForwardBufferDuration = 4.0

        // Observe item status
        statusObserver?.invalidate()
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            switch item.status {
            case .readyToPlay:
                DispatchQueue.main.async {
                    self.reconnectAttempts = 0
                    self.state = .playing
                }
                self.player.play()
            case .failed:
                self.scheduleReconnect()
            default: break
            }
        }

        // Observe timeControlStatus → best proxy for "is it actually playing"
        tcObserver?.invalidate()
        tcObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                switch player.timeControlStatus {
                case .playing:
                    self.reconnectAttempts = 0
                    if self.state != .playing { self.state = .playing }
                case .waitingToPlayAtSpecifiedRate:
                    if self.state == .playing { self.state = .buffering }
                case .paused:
                    // Force play for live TV (paused can happen if the server hiccups)
                    if player.currentItem?.status == .readyToPlay {
                        player.play()
                    }
                @unknown default: break
                }
            }
        }

        // Notifications
        let nc = NotificationCenter.default
        nc.removeObserver(self, name: .AVPlayerItemPlaybackStalled,       object: nil)
        nc.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime,      object: nil)
        nc.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)

        nc.addObserver(self, selector: #selector(onStall),  name: .AVPlayerItemPlaybackStalled,       object: item)
        nc.addObserver(self, selector: #selector(onEnd),    name: .AVPlayerItemDidPlayToEndTime,      object: item)
        nc.addObserver(self, selector: #selector(onFail),   name: .AVPlayerItemFailedToPlayToEndTime, object: item)

        player.replaceCurrentItem(with: item)
        player.play()

        // Watchdog: if still stuck loading after 15 s, reconnect
        reconnectTask?.cancel()
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self.state == .loading || self.state == .buffering {
                    self.scheduleReconnect()
                }
            }
        }
    }

    // MARK: - Notifications
    @objc private func onStall() {
        DispatchQueue.main.async { if self.state == .playing { self.state = .buffering } }
        scheduleReconnect(delay: 8)
    }
    @objc private func onEnd()  { scheduleReconnect(delay: 1.5) }
    @objc private func onFail() { scheduleReconnect() }

    // MARK: - Reconnect with exponential back-off
    private func scheduleReconnect(delay overrideDelay: Double? = nil) {
        reconnectTask?.cancel()
        reconnectAttempts += 1
        let wait = overrideDelay ?? min(Double(reconnectAttempts) * 2.5, 12.0)

        DispatchQueue.main.async { self.state = .reconnecting(self.reconnectAttempts) }

        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled, let url = self.currentURL else { return }
            await MainActor.run { self.doLoad(url: url) }
        }
    }

    deinit { stop() }
}

// MARK: - AVPlayer UIViewControllerRepresentable
struct AVPlayerLayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false   // We draw our own overlay
        vc.videoGravity = .resizeAspect
        vc.view.backgroundColor = .black
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        vc.player = player
    }
}

// MARK: - Channel Player Widget
struct ChannelPlayerWidget: View {
    let channel: Channel
    @Binding var isFullScreen: Bool
    @EnvironmentObject var tm: ThemeManager

    @StateObject private var sp = StreamPlayer()
    @State private var pulseLive = false
    @State private var showOverlay = true
    @State private var overlayTimer: Task<Void, Never>? = nil

    var playerHeight: CGFloat { isFullScreen ? UIScreen.main.bounds.height : 230 }

    var body: some View {
        ZStack {
            Color.black
            AVPlayerLayerView(player: sp.player)

            // Tap to toggle overlay
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { toggleOverlay() }

            // Top bar overlay
            if showOverlay {
                VStack {
                    HStack {
                        // Live dot + channel name
                        HStack(spacing: 6) {
                            if case .playing = sp.state {
                                Circle()
                                    .fill(tm.c.live.opacity(pulseLive ? 1 : 0.35))
                                    .frame(width: 8, height: 8)
                                    .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: pulseLive)
                                    .onAppear { pulseLive = true }
                            }
                            Text(channel.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        Spacer()
                        // Fullscreen toggle
                        Button(action: toggleFullScreen) {
                            Image(systemName: isFullScreen
                                  ? "arrow.down.right.and.arrow.up.left"
                                  : "arrow.up.left.and.arrow.down.right")
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

            // State overlays
            stateOverlay
        }
        .frame(height: isFullScreen ? UIScreen.main.bounds.height : 230)
        .ignoresSafeArea(edges: isFullScreen ? .all : [])
        .clipped()
        .onAppear { sp.play(urlString: channel.url) }
        .onChange(of: channel) { sp.play(urlString: $0.url) }
        .onDisappear { sp.stop() }
    }

    // MARK: - State overlay
    @ViewBuilder
    private var stateOverlay: some View {
        switch sp.state {
        case .loading:
            ZStack {
                Color.black.opacity(0.45)
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: tm.c.accent))
                        .scaleEffect(1.3)
                    Text("Loading…")
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
                    Text("Buffering…").font(.system(size: 12)).foregroundColor(.white)
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
                }
            }
        case .error(let msg):
            ZStack {
                Color.black.opacity(0.8)
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36)).foregroundColor(tm.c.error)
                    Text("Playback Failed")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                    Text(msg.isEmpty ? "Stream may be offline." : msg)
                        .font(.system(size: 12)).foregroundColor(Color(hex: "A0A0A0"))
                        .multilineTextAlignment(.center).padding(.horizontal)
                    Button(action: { sp.retry() }) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 24).padding(.vertical, 10)
                            .background(tm.c.accent)
                            .clipShape(Capsule())
                    }
                }
            }
        case .playing:
            EmptyView()
        }
    }

    // MARK: - Helpers
    private func toggleOverlay() {
        overlayTimer?.cancel()
        withAnimation { showOverlay.toggle() }
        if showOverlay {
            overlayTimer = Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { withAnimation { showOverlay = false } }
            }
        }
    }

    private func toggleFullScreen() {
        let goFull = !isFullScreen
        isFullScreen = goFull
        if goFull {
            setOrientation(.landscape)
        } else {
            setOrientation(.portrait)
        }
    }
}

// MARK: - Placeholder when no channel selected
struct PlayerPlaceholder: View {
    @EnvironmentObject var tm: ThemeManager

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(tm.c.surfaceElevated).frame(width: 70, height: 70)
                    Circle().stroke(tm.c.accent.opacity(0.18), lineWidth: 1).frame(width: 70, height: 70)
                    Image(systemName: "play.circle")
                        .font(.system(size: 34)).foregroundColor(tm.c.accent)
                }
                Text("Select a channel to play")
                    .font(.system(size: 14)).foregroundColor(tm.c.textSecondary)
            }
        }
        .frame(height: 230)
    }
}
