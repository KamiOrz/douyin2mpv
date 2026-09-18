import Foundation

public enum LiveError: LocalizedError {
    case invalidInput, http(Int), noStream
    public var errorDescription: String? {
        switch self {
        case .invalidInput: return "请输入抖音直播间链接、带 live_web_rid 的链接，或纯数字直播间号。"
        case .http(let code): return "抖音页面请求失败（HTTP \(code)），请稍后重试。"
        case .noStream: return "没有取得直播流。主播可能未开播，或抖音返回了验证页面。可先在浏览器确认直播状态，再重试。"
        }
    }
}

public struct LiveStream: Identifiable, Sendable, Equatable {
    public let quality: String
    public let format: String
    public let url: URL
    public var id: String { "\(format)-\(quality)" }
    public var label: String {
        let names = ["FULL_HD1": "原画 / 超清", "HD1": "高清", "SD2": "标准", "SD1": "流畅", "default": "默认"]
        return "\(names[quality] ?? quality) · \(format)"
    }
    public init(quality: String, format: String, url: URL) { self.quality = quality; self.format = format; self.url = url }
}

public enum LiveResolver {
    public static func roomID(from input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: #"^\d{5,25}$"#, options: .regularExpression) != nil { return value }
        // Also accept links copied inside share text or Markdown.
        let pattern = #"https?://[^\s<>\)\]]+"#
        guard let range = value.range(of: pattern, options: .regularExpression),
              let url = URLComponents(string: String(value[range]).replacingOccurrences(of: "\\&", with: "&")),
              let host = url.host?.lowercased(), host == "douyin.com" || host.hasSuffix(".douyin.com") else { throw LiveError.invalidInput }
        if let id = url.queryItems?.first(where: { $0.name == "live_web_rid" })?.value,
           id.range(of: #"^\d{5,25}$"#, options: .regularExpression) != nil { return id }
        // The follow feed puts the room ID in the path; anchor_id is a different ID.
        let segments = url.path.split(separator: "/")
        if (host == "www.douyin.com" || host == "douyin.com"),
           segments.count == 3, segments[0] == "follow", segments[1] == "live",
           segments[2].range(of: #"^\d{5,25}$"#, options: .regularExpression) != nil {
            return String(segments[2])
        }
        if host == "live.douyin.com", let id = url.path.split(separator: "/").first,
           id.range(of: #"^\d{5,25}$"#, options: .regularExpression) != nil { return String(id) }
        throw LiveError.invalidInput
    }

    public static func streams(in html: String) throws -> [LiveStream] {
        // Next/RSC embeds JSON within JavaScript strings. Normalize one escape layer,
        // leaving JSON Unicode escapes intact for JSONSerialization to decode.
        let text = html.replacingOccurrences(of: #"\""#, with: "\"")
        var found: [LiveStream] = []
        for (key, format) in [("hls_pull_url_map", "HLS"), ("flv_pull_url", "FLV")] {
            let regex = try NSRegularExpression(pattern: "\"" + key + "\"\\s*:\\s*(\\{[^{}]*\\})")
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text),
                      let data = String(text[range]).data(using: .utf8),
                      let map = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { continue }
                for (quality, raw) in map {
                    guard let url = URL(string: raw), ["http", "https"].contains(url.scheme), url.host != nil else { continue }
                    let item = LiveStream(quality: quality, format: format, url: url)
                    if !found.contains(where: { $0.id == item.id }) { found.append(item) }
                }
                // Only use the first room's map; do not fall through to recommended rooms.
                if !found.filter({ $0.format == format }).isEmpty { break }
            }
        }
        guard !found.isEmpty else { throw LiveError.noStream }
        let ranks = ["FULL_HD1": 0, "HD1": 1, "SD2": 2, "SD1": 3]
        return found.sorted {
            let l = ranks[$0.quality, default: 99], r = ranks[$1.quality, default: 99]
            if l != r { return l < r }
            if $0.format != $1.format { return $0.format == "HLS" }
            return $0.quality < $1.quality
        }
    }

    public static func resolve(roomID: String) async throws -> [LiveStream] {
        let url = URL(string: "https://live.douyin.com/\(roomID)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw LiveError.noStream }
        guard response.statusCode == 200 else { throw LiveError.http(response.statusCode) }
        return try streams(in: String(decoding: data, as: UTF8.self))
    }
}
