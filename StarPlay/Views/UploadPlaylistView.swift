import SwiftUI
import UniformTypeIdentifiers

struct UploadPlaylistView: View {
    let db: ChannelRepository
    let onLoaded: (Int, String, Bool, String) -> Void

    @EnvironmentObject var tm:    ThemeManager
    @EnvironmentObject var prefs: AppPreferences
    @State private var tab         = 0
    @State private var profileName = ""
    @State private var urlText     = ""
    @State private var urlError: String? = nil
    @State private var busy        = false
    @State private var progress    = 0
    @State private var filePicker  = false
    @State private var alertMsg: String? = nil

    var isArabic: Bool { prefs.languageCode == "ar" }

    var body: some View {
        ZStack {
            tm.c.background.ignoresSafeArea()
            if busy {
                SPLoadingView(
                    message: isArabic ? "جاري سحب القنوات…" : "Fetching channels…",
                    subMessage: progress > 0 ? "Parsed \(progress) channels" : "",
                    accent: tm.c.accent
                )
            } else {
                ScrollView { content.padding(.horizontal, Sp.xl) }
            }
        }
        .fileImporter(isPresented: $filePicker, allowedContentTypes: [.item], allowsMultipleSelection: false) { handleFile($0) }
        .alert("Error", isPresented: Binding(get: { alertMsg != nil }, set: { if !$0 { alertMsg = nil }})) {
            Button("OK", role: .cancel) {}
        } message: { Text(alertMsg ?? "") }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 60)
            // Header
            ZStack {
                Circle().fill(tm.c.accentSoft).frame(width: 80, height: 80)
                Image(systemName: "icloud.and.arrow.up.fill")
                    .font(.system(size: 34)).foregroundColor(tm.c.accent)
            }
            Spacer().frame(height: Sp.lg)
            Text(isArabic ? "إعداد حساب IPTV" : "Setup IPTV Profile")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(tm.c.textPrimary)

            Spacer().frame(height: Sp.xl)

            // Segment
            HStack(spacing: 0) {
                segTab(label: isArabic ? "رابط URL" : "URL Link", idx: 0)
                segTab(label: isArabic ? "ملف محلي" : "Local File", idx: 1)
            }
            .padding(4)
            .background(Color(hex: "111111"))
            .cornerRadius(Sp.r_md)
            .overlay(RoundedRectangle(cornerRadius: Sp.r_md).stroke(tm.c.border, lineWidth: 1))

            Spacer().frame(height: Sp.xl)

            // Profile name
            SPTextField(
                text: $profileName,
                placeholder: isArabic ? "اسم الحساب (اختياري)" : "Profile Name (optional)",
                accent: tm.c.accent,
                leadingIcon: "person.fill"
            )

            Spacer().frame(height: Sp.lg)

            if tab == 0 {
                VStack(spacing: Sp.xl) {
                    SPTextField(
                        text: $urlText,
                        placeholder: isArabic ? "رابط قائمة M3U" : "M3U Playlist URL",
                        isError: urlError != nil,
                        errorText: urlError,
                        accent: tm.c.accent,
                        leadingIcon: "link"
                    )
                    SPButton(title: isArabic ? "اتصال وتحميل" : "Connect & Load",
                             accent: tm.c.accent) { loadFromURL() }
                }
            } else {
                Button(action: { filePicker = true }) {
                    VStack(spacing: Sp.md) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 42)).foregroundColor(tm.c.accent)
                        Text(isArabic ? "اختر ملف M3U من الجهاز" : "Pick M3U File from Device")
                            .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        Text(".m3u  ·  .m3u8  ·  .txt")
                            .font(.system(size: 12)).foregroundColor(tm.c.textMuted)
                    }
                    .frame(maxWidth: .infinity).frame(height: 160)
                    .background(tm.c.surfaceElevated)
                    .cornerRadius(Sp.r_xl)
                    .overlay(
                        RoundedRectangle(cornerRadius: Sp.r_xl)
                            .stroke(
                                LinearGradient(colors: [tm.c.accent.opacity(0.5), tm.c.secondary.opacity(0.5)],
                                               startPoint: .leading, endPoint: .trailing),
                                lineWidth: 1.5
                            )
                    )
                }
            }
            Spacer().frame(height: 60)
        }
    }

    private func segTab(label: String, idx: Int) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.18)) { tab = idx } }) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tab == idx ? tm.c.background : tm.c.textSecondary)
                .frame(maxWidth: .infinity).padding(.vertical, Sp.md)
                .background(tab == idx ? tm.c.accent : Color.clear)
                .cornerRadius(Sp.r_sm)
        }
    }

    // MARK: - Load from URL
    private func loadFromURL() {
        let raw = urlText.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { urlError = isArabic ? "أدخل رابطاً أولاً" : "Please enter a URL first"; return }
        urlError = nil; busy = true
        Task {
            do {
                let text = try await fetchM3uText(urlString: raw)
                db.clearAll()
                let count = await Task.detached(priority: .userInitiated) {
                    parseAndInsert(text: text, allowAdult: prefs.allowAdult, db: db) { p in
                        DispatchQueue.main.async { progress = p }
                    }
                }.value
                await MainActor.run {
                    busy = false
                    if count > 0 {
                        let n = profileName.isEmpty ? (isArabic ? "حساب السيرفر" : "Server Profile") : profileName
                        onLoaded(count, n, true, raw)
                    } else {
                        alertMsg = isArabic ? "لم يتم العثور على قنوات." : "No channels found. Check the URL."
                    }
                }
            } catch {
                await MainActor.run { busy = false; alertMsg = error.localizedDescription }
            }
        }
    }

    // MARK: - Load from file
    private func handleFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            busy = true
            Task.detached(priority: .userInitiated) {
                guard url.startAccessingSecurityScopedResource() else {
                    await MainActor.run { busy = false; alertMsg = "Cannot access file." }
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    guard isLikelyM3u(text: text) else {
                        await MainActor.run {
                            busy = false
                            alertMsg = isArabic
                                ? "الملف غير صالح. اختر ملف m3u أو m3u8."
                                : "Invalid file. Please choose an .m3u or .m3u8 file."
                        }
                        return
                    }
                    await MainActor.run { db.clearAll() }
                    let count = parseAndInsert(text: text, allowAdult: prefs.allowAdult, db: db) { p in
                        DispatchQueue.main.async { progress = p }
                    }
                    // Save bookmark so the app can re-open the file next launch
                    prefs.saveFileBookmark(for: url)
                    await MainActor.run {
                        busy = false
                        if count > 0 {
                            let n = profileName.isEmpty ? (isArabic ? "حسابي المحلي" : "My Local Profile") : profileName
                            onLoaded(count, n, false, url.absoluteString)
                        } else {
                            alertMsg = isArabic ? "لا توجد قنوات في هذا الملف." : "No channels found in this file."
                        }
                    }
                } catch {
                    await MainActor.run { busy = false; alertMsg = error.localizedDescription }
                }
            }
        case .failure(let e):
            alertMsg = e.localizedDescription
        }
    }
}
