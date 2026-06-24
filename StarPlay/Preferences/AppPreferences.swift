import Foundation

final class AppPreferences: ObservableObject {
    private let ud = UserDefaults.standard
    private enum K {
        static let hasProfile    = "sp_has_profile"
        static let profileName   = "sp_profile_name"
        static let sourceIsUrl   = "sp_source_is_url"
        static let sourcePath    = "sp_source_path"
        static let allowAdult    = "sp_allow_adult"
        static let languageCode  = "sp_language_code"
        static let isDefault     = "sp_is_default_source"
        static let lastFetch     = "sp_last_fetch_ts"
        static let fileBookmark  = "sp_file_bookmark"
    }

    @Published var hasProfile: Bool    { didSet { ud.set(hasProfile,   forKey: K.hasProfile) } }
    @Published var profileName: String { didSet { ud.set(profileName,  forKey: K.profileName) } }
    @Published var sourceIsUrl: Bool   { didSet { ud.set(sourceIsUrl,  forKey: K.sourceIsUrl) } }
    @Published var sourcePath: String  { didSet { ud.set(sourcePath,   forKey: K.sourcePath) } }
    @Published var allowAdult: Bool    { didSet { ud.set(allowAdult,   forKey: K.allowAdult) } }
    @Published var languageCode: String{ didSet { ud.set(languageCode, forKey: K.languageCode) } }
    @Published var isDefaultSource: Bool{ didSet { ud.set(isDefaultSource, forKey: K.isDefault) } }

    var lastFetchTimestamp: Double {
        get { ud.double(forKey: K.lastFetch) }
        set { ud.set(newValue, forKey: K.lastFetch) }
    }

    // MARK: - File bookmark (for security-scoped local files)
    func saveFileBookmark(for url: URL) {
        let data = try? url.bookmarkData(options: .minimalBookmark,
                                         includingResourceValuesForKeys: nil,
                                         relativeTo: nil)
        ud.set(data, forKey: K.fileBookmark)
    }

    func resolveFileBookmark() -> URL? {
        guard let data = ud.data(forKey: K.fileBookmark) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
    }

    // MARK: - Init
    init() {
        hasProfile      = ud.bool(forKey: K.hasProfile)
        profileName     = ud.string(forKey: K.profileName) ?? ""
        sourceIsUrl     = ud.bool(forKey: K.sourceIsUrl)
        sourcePath      = ud.string(forKey: K.sourcePath) ?? ""
        allowAdult      = ud.bool(forKey: K.allowAdult)
        languageCode    = ud.string(forKey: K.languageCode) ?? ""
        isDefaultSource = ud.bool(forKey: K.isDefault)
    }

    func logout() {
        if let bundle = Bundle.main.bundleIdentifier {
            ud.removePersistentDomain(forName: bundle)
        }
        hasProfile      = false
        profileName     = ""
        sourceIsUrl     = false
        sourcePath      = ""
        allowAdult      = false
        languageCode    = ""
        isDefaultSource = false
    }
}
