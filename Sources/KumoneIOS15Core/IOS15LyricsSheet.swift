import SwiftUI

struct IOS15LyricsSheet: View {
    let track: Track
    @Environment(\.presentationMode) private var presentationMode

    @State private var originalLines: [String] = []
    @State private var translatedLines: [String] = []
    @State private var isLoading = true
    @State private var message: String?

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("正在加载歌词")
                } else if let message {
                    VStack(spacing: 12) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 34))
                            .foregroundColor(.secondary)
                        Text(message)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(Array(originalLines.enumerated()), id: \.offset) { index, line in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(line)
                                        .font(.title3.weight(.medium))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if index < translatedLines.count,
                                       !translatedLines[index].isEmpty {
                                        Text(translatedLines[index])
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationBarTitle(track.name, displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .task {
            await loadLyrics()
        }
    }

    private func loadLyrics() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await NeteaseAPI.lyric(id: track.id)
            if response.nolyric == true {
                message = "这是一首纯音乐"
                return
            }
            let originals = Self.lines(from: response.lrc?.lyric)
            guard !originals.isEmpty else {
                message = "暂未找到歌词"
                return
            }
            originalLines = originals
            translatedLines = Self.lines(from: response.tlyric?.lyric)
        } catch {
            message = "歌词加载失败，请稍后重试"
        }
    }

    private static func lines(from raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let components = rawLine.split(separator: "]", maxSplits: 1, omittingEmptySubsequences: false)
            let text = components.count > 1 ? String(components[1]) : String(rawLine)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
