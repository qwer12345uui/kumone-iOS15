import CoreFoundation
import Foundation

/// Lightweight offline Japanese lyric transcription for the iOS 15 core.
/// It uses the system tokenizer and does not contact external providers.
enum IOS15RomajiTranscriber {
    private static let kanaRanges: [ClosedRange<UInt32>] = [
        0x3040...0x309F,
        0x30A0...0x30FF,
        0xFF66...0xFF9D,
    ]

    static func containsKana(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            kanaRanges.contains { $0.contains(scalar.value) }
        }
    }

    static func isJapanese(_ texts: [String]) -> Bool {
        let candidates = texts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !candidates.isEmpty else { return false }
        let kanaLines = candidates.count(where: containsKana)
        return kanaLines >= 3 || Double(kanaLines) / Double(candidates.count) >= 0.2
    }

    static func transcribe(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let source = trimmed as CFString
        let range = CFRangeMake(0, CFStringGetLength(source))
        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            source,
            range,
            kCFStringTokenizerUnitWordBoundary,
            Locale(identifier: "ja_JP") as CFLocale
        )

        var pieces: [String] = []
        var transcribedAny = false
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let original = CFStringCreateWithSubstring(kCFAllocatorDefault, source, tokenRange) as String? ?? ""
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(
                tokenizer,
                kCFStringTokenizerAttributeLatinTranscription
            ) as? String, !latin.isEmpty {
                pieces.append(latin)
                transcribedAny = true
            } else if !original.trimmingCharacters(in: .whitespaces).isEmpty {
                pieces.append(original)
            }
        }

        guard transcribedAny else { return nil }
        let romaji = pieces.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !romaji.isEmpty, !isEquivalent(romaji, trimmed) else { return nil }
        return romaji
    }

    private static func isEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        func squash(_ value: String) -> String {
            value.lowercased().filter { !$0.isWhitespace }
        }
        return squash(lhs) == squash(rhs)
    }
}
