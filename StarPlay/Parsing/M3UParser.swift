import Foundation

// MARK: - Adult filter
func isStrictlyAdult(name: String, category: String) -> Bool {
    let t = "\(name) \(category)".lowercased()
    return ["xxx","porn","adults only","brazzers","playboy","18+","vivid","hustler"].contains(where: t.contains)
}

// MARK: - M3U detection
func isLikelyM3u(text: String) -> Bool {
    let lines = text.components(separatedBy: .newlines)
    var sawInfo = false, sawStream = false
    for line in lines.prefix(50) {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { continue }
        if t.uppercased().hasPrefix("#EXTM3U")  { return true }
        if t.uppercased().hasPrefix("#EXTINF")  { sawInfo = true }
        if !t.hasPrefix("#") && (t.hasPrefix("http://") || t.hasPrefix("https://") || t.hasPrefix("rtmp://") || t.hasPrefix("rtsp://")) { sawStream = true }
        if sawInfo && sawStream { return true }
    }
    return sawInfo || sawStream
}

// MARK: - Fetch URL
func fetchM3uText(urlString: String) async throws -> String {
    guard let url = URL(string: urlString) else { throw URLError(.badURL) }
    var req = URLRequest(url: url, timeoutInterval: 20)
    req.setValue("VLC/3.0.18 LibVLC/3.0.18", forHTTPHeaderField: "User-Agent")
    req.setValue("*/*", forHTTPHeaderField: "Accept")
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    return String(data: data, encoding: .utf8)
        ?? String(data: data, encoding: .isoLatin1)
        ?? ""
}

// MARK: - Parse & batch insert
@discardableResult
func parseAndInsert(
    text: String,
    allowAdult: Bool,
    db: ChannelRepository,
    onProgress: @escaping (Int) -> Void
) -> Int {
    let lines   = text.components(separatedBy: .newlines)
    var batch:  [Channel] = []
    var total   = 0

    var name     = "Unknown Channel"
    var category = "General"
    var logo     = ""

    let groupRx = try? NSRegularExpression(pattern: #"group-title="([^"]+)""#)
    let logoRx  = try? NSRegularExpression(pattern: #"tvg-logo="([^"]+)""#)

    func first(_ rx: NSRegularExpression?, in s: String) -> String? {
        guard let rx else { return nil }
        let ns = s as NSString
        guard let m = rx.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let r = m.range(at: 1)
        return r.location != NSNotFound ? ns.substring(with: r) : nil
    }

    for line in lines {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.uppercased().hasPrefix("#EXTINF:") {
            category = first(groupRx, in: t) ?? "General"
            logo     = first(logoRx,  in: t) ?? ""
            if let ci = t.lastIndex(of: ",") {
                name = String(t[t.index(after: ci)...]).trimmingCharacters(in: .whitespaces)
            } else { name = "Unknown Channel" }
        } else if !t.isEmpty && !t.hasPrefix("#") {
            if allowAdult || !isStrictlyAdult(name: name, category: category) {
                batch.append(Channel(name: name, url: t, category: category, logo: logo))
                if batch.count >= 1000 {
                    db.insertBatch(batch)
                    total += batch.count
                    onProgress(total)
                    batch.removeAll(keepingCapacity: true)
                }
            }
            name = "Unknown Channel"; category = "General"; logo = ""
        }
    }
    if !batch.isEmpty { db.insertBatch(batch); total += batch.count; onProgress(total) }
    return total
}
