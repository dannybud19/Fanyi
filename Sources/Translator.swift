import Foundation

struct TranslationResult {
    let translatedText: String
    let detectedSourceLanguage: String
    let sourceRomanization: String?
    let targetRomanization: String?
    let didAutoFlip: Bool
    let effectiveTargetLanguage: TargetLanguage
}

enum TranslatorError: Error {
    case invalidURL
    case network(Error)
    case decodingFailed
}

enum Translator {
    static let maxInputLength = 8000
    static let chunkSize = 1200
    static let requestTimeout: TimeInterval = 8

    // MARK: - Percent encoding

    /// Encodes using an explicit ASCII unreserved set. URLComponents leaves `+` unencoded,
    /// and CharacterSet.alphanumerics includes non-ASCII (e.g. Chinese) characters.
    static func percentEncodeQuery(_ text: String) -> String {
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    // MARK: - Chunking

    static func chunk(_ text: String) -> [String] {
        if text.count <= chunkSize { return [text] }
        var chunks: [String] = []
        var current = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineStr = String(line)
            if current.isEmpty {
                current = lineStr
            } else if current.count + 1 + lineStr.count <= chunkSize {
                current += "\n" + lineStr
            } else {
                chunks.append(current)
                current = lineStr
            }
            while current.count > chunkSize {
                let idx = current.index(current.startIndex, offsetBy: chunkSize)
                chunks.append(String(current[..<idx]))
                current = String(current[idx...])
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    // MARK: - Language code helpers

    static func langBase(_ code: String) -> String {
        String(code.split(separator: "-").first ?? Substring(code)).lowercased()
    }

    // MARK: - Single-chunk fetch + parse

    private struct ChunkResult {
        let translated: String
        let detected: String
        let sourceRomanization: String?
        let targetRomanization: String?
    }

    private static func fetchChunk(_ text: String, targetCode: String) async throws -> ChunkResult {
        let encoded = percentEncodeQuery(text)
        let urlString = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=\(targetCode)&dt=t&dt=rm&q=\(encoded)"
        guard let url = URL(string: urlString) else { throw TranslatorError.invalidURL }

        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "GET"

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranslatorError.network(error)
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any] else {
            throw TranslatorError.decodingFailed
        }

        var translated = ""
        var sourceRomanization: String?
        var targetRomanization: String?

        for case let seg as [Any] in segments {
            guard !seg.isEmpty else { continue }
            if let text0 = seg[0] as? String {
                translated += text0
            } else {
                // Romanization segment. Layout varies:
                //  - [null, null, "<targetRomanization>"] when target is Chinese
                //  - [null, null, null, "<sourceRomanization>"] when source is Chinese
                if seg.count > 2, let t = seg[2] as? String { targetRomanization = t }
                if seg.count > 3, let s = seg[3] as? String { sourceRomanization = s }
            }
        }

        let detected = (root.count > 2 ? root[2] as? String : nil) ?? "auto"
        return ChunkResult(translated: translated, detected: detected,
                            sourceRomanization: sourceRomanization, targetRomanization: targetRomanization)
    }

    // MARK: - Multi-chunk combine

    private static func translateChunks(_ chunks: [String], targetCode: String) async throws
        -> (text: String, detected: String, srcRom: String?, tgtRom: String?) {
        var parts: [String] = []
        var srcParts: [String] = []
        var tgtParts: [String] = []
        var detected = "auto"

        for (i, c) in chunks.enumerated() {
            let r = try await fetchChunk(c, targetCode: targetCode)
            parts.append(r.translated)
            if i == 0 { detected = r.detected }
            if let s = r.sourceRomanization { srcParts.append(s) }
            if let t = r.targetRomanization { tgtParts.append(t) }
        }

        return (
            parts.joined(),
            detected,
            srcParts.isEmpty ? nil : srcParts.joined(separator: " "),
            tgtParts.isEmpty ? nil : tgtParts.joined(separator: " ")
        )
    }

    // MARK: - Top-level translate with auto-flip

    static func translate(text: String, target: TargetLanguage) async throws -> TranslationResult {
        let capped = String(text.prefix(maxInputLength))
        let chunks = chunk(capped)
        let first = try await translateChunks(chunks, targetCode: target.rawValue)

        if langBase(first.detected) == langBase(target.rawValue) {
            let fallback: TargetLanguage = (target == .english) ? .simplifiedChinese : .english
            let second = try await translateChunks(chunks, targetCode: fallback.rawValue)
            return TranslationResult(
                translatedText: second.text,
                detectedSourceLanguage: second.detected,
                sourceRomanization: second.srcRom,
                targetRomanization: second.tgtRom,
                didAutoFlip: true,
                effectiveTargetLanguage: fallback
            )
        }

        return TranslationResult(
            translatedText: first.text,
            detectedSourceLanguage: first.detected,
            sourceRomanization: first.srcRom,
            targetRomanization: first.tgtRom,
            didAutoFlip: false,
            effectiveTargetLanguage: target
        )
    }
}
