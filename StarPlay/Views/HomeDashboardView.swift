import SwiftUI

private let DEFAULT_URL = "https://roamingadmin.incentivetravel.co.ke/ALFA_DATA/playlist.m3u"
private let REFRESH_INTERVAL: Double = 30 * 60   // 30 min background refresh

struct HomeDashboardView: View {
    let db: ChannelRepository
    let onLogout: () -> Void
    let onAdultChanged: (Bool) -> Void
    let onSwitchSource: () -> Void

    @EnvironmentObject var tm:    ThemeManager
    @EnvironmentObject var prefs: AppPreferences

    // Player
    @State private var selectedChannel: Channel? = nil
    @State private var isFullScreen = false

    // Drawer
    @State private var drawerOpen = false

    // Search / filter
    @State private var search   = ""
    @State private var category = "__all__"

    // Data
    @State private var channels:   [Channel] = []
    @State private var categories: [String]  = []
    @State private var total       = 0
    @State private var offset      = 0
    @State private var loadingMore = false

    private let cols = [GridItem(.adaptive(minimum: 260), spacing: 12)]

    var isArabic: Bool { prefs.languageCode == "ar" }

    var body: some View {
        ZStack(alignment: .leading) {
            tm.c.background.ignoresSafeArea()

            // ── Main column ──
            VStack(spacing: 0) {
                // Player zone
                Group {
                    if let ch = selectedChannel {
                        ChannelPlayerWidget(channel: ch, isFullScreen: $isFullScreen)
                    } else if !isFullScreen {
                        PlayerPlaceholder()
                    }
                }

                // Content (hidden in fullscreen)
                if !isFullScreen {
                    topBar
                    searchBar
                        .padding(.horizontal, Sp.lg)
                        .padding(.top, Sp.sm)
                    categoryRow
                        .padding(.top, Sp.sm)
                    channelContent
                }
            }
            .ignoresSafeArea(edges: isFullScreen ? .all : [])

            // ── Drawer scrim ──
            if drawerOpen {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture { closeDrawer() }
                    .zIndex(10)
            }

            // ── Drawer panel ──
            if drawerOpen {
                DrawerPanel(
                    onLogout:      { closeDrawer(); DispatchQueue.main.asyncAfter(deadline: .now()+0.3){ onLogout() } },
                    onSwitchSource:{ closeDrawer(); DispatchQueue.main.asyncAfter(deadline: .now()+0.3){ onSwitchSource() } },
                    onAdultChanged:{ v in closeDrawer(); onAdultChanged(v) }
                )
                .frame(width: 300)
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(11)
                .ignoresSafeArea()
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: drawerOpen)
        .onAppear { loadInitial() }
        .onChange(of: category) { _ in loadInitial() }
        .onChange(of: search) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { loadInitial() }
        }
        .task {
            guard prefs.isDefaultSource else { return }
            while true {
                try? await Task.sleep(nanoseconds: UInt64(REFRESH_INTERVAL * 1_000_000_000))
                if let text = try? await fetchM3uText(urlString: DEFAULT_URL) {
                    db.clearAll()
                    _ = parseAndInsert(text: text, allowAdult: prefs.allowAdult, db: db) { _ in }
                    prefs.lastFetchTimestamp = Date().timeIntervalSince1970
                }
            }
        }
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack(spacing: Sp.md) {
            // Hamburger
            Button(action: { withAnimation { drawerOpen = true } }) {
                ZStack {
                    Circle()
                        .fill(tm.c.surfaceElevated)
                        .frame(width: 44, height: 44)
                    Circle()
                        .stroke(tm.c.border, lineWidth: 0.5)
                        .frame(width: 44, height: 44)
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 18))
                        .foregroundColor(tm.c.textPrimary)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(prefs.profileName.isEmpty ? "StarPlay" : prefs.profileName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(tm.c.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Circle().fill(tm.c.accent).frame(width: 6, height: 6)
                    Text("\(total) \(isArabic ? "قناة" : "channels")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(tm.c.accent)
                }
            }
            Spacer()

            // Theme dot indicator
            HStack(spacing: 5) {
                ForEach(AppTheme.allCases) { t in
                    Circle()
                        .fill(t.accentPreview)
                        .frame(width: t == tm.theme ? 9 : 5, height: t == tm.theme ? 9 : 5)
                        .animation(.spring(), value: tm.theme)
                }
            }
            .onTapGesture { withAnimation { drawerOpen = true } }
        }
        .padding(.horizontal, Sp.lg)
        .padding(.vertical, Sp.md)
    }

    // MARK: - Search bar
    private var searchBar: some View {
        HStack(spacing: Sp.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(search.isEmpty ? tm.c.textMuted : tm.c.accent)
                .font(.system(size: 15))
            TextField("", text: $search)
                .foregroundColor(tm.c.textPrimary)
                .font(.system(size: 15))
                .autocorrectionDisabled()
                .placeholder(when: search.isEmpty) {
                    Text(isArabic ? "ابحث عن قناة…" : "Search channels…")
                        .foregroundColor(tm.c.textMuted)
                        .font(.system(size: 15))
                }
            if !search.isEmpty {
                Button(action: { search = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(tm.c.textMuted)
                }
            }
        }
        .padding(.horizontal, Sp.md)
        .frame(height: 46)
        .background(tm.c.surfaceElevated)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(search.isEmpty ? tm.c.border : tm.c.accent.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Category chips row
    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Sp.sm) {
                catChip(label: isArabic ? "الكل" : "All", key: "__all__")
                ForEach(categories, id: \.self) { cat in
                    catChip(label: cat, key: cat)
                }
            }
            .padding(.horizontal, Sp.lg)
            .padding(.vertical, Sp.sm)
        }
    }

    private func catChip(label: String, key: String) -> some View {
        let active = category == key
        return Button(action: { category = key }) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(active ? tm.c.background : tm.c.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(active ? tm.c.accent : tm.c.surfaceElevated)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(active ? Color.clear : tm.c.border, lineWidth: 0.5))
                .shadow(color: active ? tm.c.accentGlow.opacity(0.5) : .clear, radius: 6)
        }
        .animation(.easeOut(duration: 0.15), value: active)
    }

    // MARK: - Channel content area
    @ViewBuilder
    private var channelContent: some View {
        if channels.isEmpty && !loadingMore {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(Array(channels.enumerated()), id: \.element.url) { idx, ch in
                        ChannelCardView(
                            channel: ch,
                            index: idx,
                            isSelected: selectedChannel?.url == ch.url,
                            onTap: { selectedChannel = ch }
                        )
                        .onAppear {
                            if idx == channels.count - 10 { loadMore() }
                        }
                    }
                    if loadingMore {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: tm.c.accent))
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    }
                }
                .padding(.horizontal, Sp.md)
                .padding(.bottom, Sp.xl3)
            }
        }
    }

    // MARK: - Empty state
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().fill(tm.c.surfaceElevated).frame(width: 90, height: 90)
                Image(systemName: "magnifyingglass").font(.system(size: 36)).foregroundColor(tm.c.textMuted)
            }
            Text(search.isEmpty
                 ? (isArabic ? "لا توجد قنوات" : "No channels yet")
                 : (isArabic ? "لا نتائج لـ \"\(search)\"" : "No results for \"\(search)\""))
                .font(.system(size: 16, weight: .semibold)).foregroundColor(tm.c.textPrimary)
            Text(isArabic ? "جرب كلمة أخرى" : "Try a different search or category")
                .font(.system(size: 13)).foregroundColor(tm.c.textSecondary)
            Spacer()
        }
        .padding(Sp.xl)
    }

    // MARK: - Data
    private func loadInitial() {
        loadingMore = true
        Task.detached(priority: .userInitiated) {
            let cats  = db.getCategories()
            let tot   = db.getTotalCount(category: category, search: search)
            let page  = db.getPage(category: category, search: search, offset: 0, limit: 60)
            await MainActor.run {
                categories  = cats
                total       = tot
                channels    = page
                offset      = 0
                loadingMore = false
            }
        }
    }

    private func loadMore() {
        guard !loadingMore, channels.count < total else { return }
        loadingMore = true
        let nextOff = offset + 60
        Task.detached(priority: .userInitiated) {
            let page = db.getPage(category: category, search: search, offset: nextOff, limit: 60)
            await MainActor.run {
                channels   += page
                offset      = nextOff
                loadingMore = false
            }
        }
    }

    private func closeDrawer() { withAnimation { drawerOpen = false } }
}

// MARK: - Drawer Panel
private struct DrawerPanel: View {
    let onLogout: () -> Void
    let onSwitchSource: () -> Void
    let onAdultChanged: (Bool) -> Void

    @EnvironmentObject var tm:    ThemeManager
    @EnvironmentObject var prefs: AppPreferences
    @State private var adult: Bool = false

    var isArabic: Bool { prefs.languageCode == "ar" }

    var body: some View {
        ZStack(alignment: .leading) {
            tm.c.surface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                // ── Header ──
                ZStack(alignment: .bottom) {
                    LinearGradient(
                        colors: [tm.c.accentSoft.opacity(0.7), tm.c.surface],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 200)
                    VStack(spacing: 10) {
                        ZStack {
                            Circle().fill(tm.c.accentSoft).frame(width: 72, height: 72)
                            Circle().stroke(tm.c.accent.opacity(0.3), lineWidth: 1.5).frame(width: 72, height: 72)
                            Image(systemName: "play.tv.fill")
                                .font(.system(size: 32)).foregroundColor(tm.c.accent)
                        }
                        Text("StarPlay").font(.system(size: 20, weight: .black, design: .rounded)).foregroundColor(tm.c.textPrimary)
                        Text(prefs.profileName.isEmpty ? "c0derz" : prefs.profileName)
                            .font(.system(size: 12)).foregroundColor(tm.c.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Sp.xl)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // ── Theme picker ──
                        sectionHeader(isArabic ? "المظهر" : "Theme")
                        HStack(spacing: Sp.md) {
                            ForEach(AppTheme.allCases) { t in
                                ThemeChip(theme: t, isSelected: tm.theme == t) {
                                    withAnimation(.spring()) { tm.theme = t }
                                }
                            }
                        }
                        .padding(.horizontal, Sp.lg)
                        .padding(.bottom, Sp.xl)

                        Divider().background(tm.c.border).padding(.horizontal, Sp.lg)
                        Spacer().frame(height: Sp.xl)

                        // ── Settings ──
                        sectionHeader(isArabic ? "الإعدادات" : "Settings")

                        // Adult toggle
                        HStack {
                            Image(systemName: "eye.slash.fill")
                                .foregroundColor(tm.c.textSecondary).frame(width: 22)
                            Text(isArabic ? "محتوى +18" : "Show 18+ Content")
                                .font(.system(size: 15)).foregroundColor(tm.c.textPrimary)
                            Spacer()
                            Toggle("", isOn: $adult)
                                .labelsHidden()
                                .tint(tm.c.accent)
                                .onChange(of: adult) { v in onAdultChanged(v) }
                        }
                        .padding(.horizontal, Sp.lg)
                        .padding(.bottom, Sp.lg)

                        // Source indicator
                        HStack(spacing: Sp.sm) {
                            Image(systemName: prefs.isDefaultSource ? "checkmark.icloud.fill" : "folder.fill")
                                .foregroundColor(prefs.isDefaultSource ? tm.c.accent : tm.c.secondary)
                            Text(isArabic
                                 ? (prefs.isDefaultSource ? "القائمة الافتراضية" : "قائمة مخصصة")
                                 : (prefs.isDefaultSource ? "Default playlist (auto-updated)" : "Custom playlist (manual)"))
                                .font(.system(size: 12)).foregroundColor(tm.c.textSecondary)
                        }
                        .padding(Sp.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(tm.c.surfaceElevated)
                        .cornerRadius(Sp.r_md)
                        .padding(.horizontal, Sp.lg)
                        .padding(.bottom, Sp.sm)

                        // Switch source
                        Button(action: onSwitchSource) {
                            Label(
                                isArabic ? "تغيير مصدر القائمة" : "Switch Playlist Source",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(tm.c.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .overlay(RoundedRectangle(cornerRadius: Sp.r_md).stroke(tm.c.accent.opacity(0.35), lineWidth: 1))
                        }
                        .padding(.horizontal, Sp.lg)
                    }
                }

                Spacer()

                // ── Logout ──
                Button(action: onLogout) {
                    Label(isArabic ? "تغيير القائمة" : "Change Playlist", systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(hex: "FF3B30"))
                        .cornerRadius(Sp.r_md)
                }
                .padding(.horizontal, Sp.lg)
                .padding(.bottom, Sp.xl)
            }
        }
        .onAppear { adult = prefs.allowAdult }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(tm.c.accent)
            .tracking(0.8)
            .padding(.horizontal, Sp.lg)
            .padding(.bottom, Sp.sm)
    }
}

// MARK: - Theme Chip
private struct ThemeChip: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    @EnvironmentObject var tm: ThemeManager

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(theme.accentPreview.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Circle()
                        .stroke(isSelected ? theme.accentPreview : Color(hex: "303030"), lineWidth: isSelected ? 2 : 1)
                        .frame(width: 44, height: 44)
                    Image(systemName: theme.icon)
                        .font(.system(size: 18))
                        .foregroundColor(theme.accentPreview)
                }
                Text(theme.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? theme.accentPreview : Color(hex: "707070"))
            }
            .frame(maxWidth: .infinity)
        }
        .scaleEffect(isSelected ? 1.06 : 1)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - Placeholder text helper
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: .leading) {
            if shouldShow { placeholder() }
            self
        }
    }
}
