import SwiftUI

private let DEFAULT_URL = "https://roamingadmin.incentivetravel.co.ke/ALFA_DATA/playlist.m3u"

struct AppNavigator: View {
    @EnvironmentObject var tm:    ThemeManager
    @EnvironmentObject var prefs: AppPreferences
    @State private var db       = ChannelRepository()
    @State private var screen: Screen = .splash
    @State private var progress = 0

    enum Screen {
        case splash, loadingSaved, langSelect, sourceChoice,
             loadingDefault, uploadPlaylist, home
    }

    var body: some View {
        Group {
            switch screen {
            case .splash:
                SplashView { screen = prefs.hasProfile ? .loadingSaved : .langSelect }

            case .loadingSaved:
                SPLoadingView(
                    message: isArabic ? "جاري تحميل ملفك الشخصي…" : "Loading profile…",
                    subMessage: progress > 0 ? "Parsed \(progress) channels" : "",
                    accent: tm.c.accent
                )
                .task { await loadSaved() }

            case .langSelect:
                LanguageSelectionView { lang in
                    prefs.languageCode = lang
                    screen = .sourceChoice
                }

            case .sourceChoice:
                SourceChoiceView(
                    onUseDefault: { screen = .loadingDefault },
                    onUseCustom:  { screen = .uploadPlaylist }
                )

            case .loadingDefault:
                SPLoadingView(
                    message: isArabic ? "جاري سحب القنوات…" : "Fetching channels…",
                    subMessage: progress > 0 ? "Parsed \(progress) channels" : "",
                    accent: tm.c.accent
                )
                .task { await loadDefault() }

            case .uploadPlaylist:
                UploadPlaylistView(db: db) { count, name, isUrl, path in
                    prefs.hasProfile      = true
                    prefs.profileName     = name
                    prefs.sourceIsUrl     = isUrl
                    prefs.sourcePath      = path
                    prefs.isDefaultSource = false
                    prefs.lastFetchTimestamp = Date().timeIntervalSince1970
                    screen = .home
                }

            case .home:
                HomeDashboardView(db: db,
                    onLogout: {
                        prefs.logout()
                        screen = .langSelect
                    },
                    onAdultChanged: { _ in screen = .loadingSaved },
                    onSwitchSource: { screen = .sourceChoice }
                )
            }
        }
        .animation(.easeInOut(duration: 0.22), value: screen)
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }

    var isArabic: Bool { prefs.languageCode == "ar" }

    // MARK: - Loaders
    private func loadSaved() async {
        progress = 0
        db.clearAll()
        do {
            let count: Int
            if prefs.sourceIsUrl {
                let text = try await fetchM3uText(urlString: prefs.sourcePath)
                count = await Task.detached(priority: .userInitiated) {
                    parseAndInsert(text: text, allowAdult: prefs.allowAdult, db: db) { p in
                        DispatchQueue.main.async { progress = p }
                    }
                }.value
            } else {
                guard let url = prefs.resolveFileBookmark() else {
                    await go(prefs.isDefaultSource ? .sourceChoice : .uploadPlaylist); return
                }
                guard url.startAccessingSecurityScopedResource() else {
                    await go(.uploadPlaylist); return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                count = await Task.detached(priority: .userInitiated) {
                    parseAndInsert(text: text, allowAdult: prefs.allowAdult, db: db) { p in
                        DispatchQueue.main.async { progress = p }
                    }
                }.value
            }
            await go(count > 0 ? .home : (prefs.isDefaultSource ? .sourceChoice : .uploadPlaylist))
        } catch {
            await go(prefs.isDefaultSource ? .sourceChoice : .uploadPlaylist)
        }
    }

    private func loadDefault() async {
        progress = 0
        do {
            let text = try await fetchM3uText(urlString: DEFAULT_URL)
            db.clearAll()
            let count = await Task.detached(priority: .userInitiated) {
                parseAndInsert(text: text, allowAdult: prefs.allowAdult, db: db) { p in
                    DispatchQueue.main.async { progress = p }
                }
            }.value
            if count > 0 {
                prefs.hasProfile      = true
                prefs.profileName     = "Premium IPTV"
                prefs.sourceIsUrl     = true
                prefs.sourcePath      = DEFAULT_URL
                prefs.isDefaultSource = true
                prefs.lastFetchTimestamp = Date().timeIntervalSince1970
                await go(.home)
            } else { await go(.sourceChoice) }
        } catch { await go(.sourceChoice) }
    }

    @MainActor private func go(_ s: Screen) { screen = s }
}
