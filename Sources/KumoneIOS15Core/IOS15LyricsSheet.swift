import Foundation
import SwiftUI

struct IOS15LyricsSheet: View {
    let track: Track
    @ObservedObject var store: IOS15MusicStore
    @Environment(\.presentationMode) private var presentationMode

    @State private var originalLines: [TimedLyricLine] = []
    @State private var translatedByTimestamp: [Int: String] = [:]
    @State private var isLoading = true
    @State private var message: String?

    private var activeLineID: Int? {
        guard let first = originalLines.first else { return nil }
        return originalLines.last(where: { $0.time <= store.playbackTime })?.id ?? first.id
    }

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
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 24) {
                                ForEach(originalLines) { line in
                                    lyricRow(line, isActive: line.id == activeLineID)
                                        .id(line.id)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 54)
                        }
                        .onAppear {
                            scrollActiveLine(with: proxy)
                        }
                        .onChange(of: activeLineID) { _ in
                            scrollActiveLine(with: proxy)
                        }
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
        .ios15EdgeBack {
            presentationMode.wrappedValue.dismiss()
        }
        .task {
            await loadLyrics()
        }
    }

    @ViewBuilder
    private func lyricRow(_ line: TimedLyricLine, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(line.text)
                .font(isActive ? .title2.weight(.bold) : .title3.weight(.medium))
                .foregroundColor(isActive ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .scaleEffect(isActive ? 1.025 : 1, anchor: .leading)

            if let translation = translatedByTimestamp[line.timestampKey], !translation.isEmpty {
                Text(translation)
                    .font(.subheadline)
                    .foregroundColor(isActive ? .primary.opacity(0.72) : .secondary.opacity(0.76))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    private func scrollActiveLine(with proxy: ScrollViewProxy) {
        guard let activeLineID else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            proxy.scrollTo(activeLineID, anchor: .center)
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
                message = "暂未找到带时间轴的歌词"
                return
            }
            originalLines = originals
            var translations: [Int: String] = [:]
            for line in Self.lines(from: response.tlyric?.lyric) {
                translations[line.timestampKey] = line.text
            }
            translatedByTimestamp = translations
        } catch {
            message = "歌词加载失败，请稍后重试"
        }
    }

    private static func lines(from raw: String?) -> [TimedLyricLine] {
        guard let raw else { return [] }
        let expression = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2}(?:\.\d{1,3})?)\]"#)
        guard let expression else { return [] }

        var lines: [TimedLyricLine] = []
        var index = 0
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let source = String(rawLine)
            let range = NSRange(source.startIndex..., in: source)
            let matches = expression.matches(in: source, range: range)
            guard let finalMatch = matches.last,
                  let textRange = Range(NSRange(location: finalMatch.range.upperBound,
                                                 length: range.upperBound - finalMatch.range.upperBound),
                                        in: source)
            else { continue }

            let text = String(source[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            for match in matches {
                guard let timestampRange = Range(match.range(at: 1), in: source),
                      let timestamp = timestamp(from: String(source[timestampRange]))
                else { continue }
                lines.append(TimedLyricLine(id: index, time: timestamp, text: text))
                index += 1
            }
        }
        return lines.sorted { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
    }

    private static func timestamp(from text: String) -> TimeInterval? {
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else {
            return nil
        }
        return minutes * 60 + seconds
    }
}

private struct TimedLyricLine: Identifiable {
    let id: Int
    let time: TimeInterval
    let text: String

    var timestampKey: Int {
        Int((time * 1_000).rounded())
    }
}

private struct IOS15EdgeBackGesture: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { value in
                    guard value.startLocation.x <= 28,
                          value.translation.width >= 80,
                          abs(value.translation.height) <= 40
                    else { return }
                    action()
                }
        )
    }
}

private extension View {
    func ios15EdgeBack(_ action: @escaping () -> Void) -> some View {
        modifier(IOS15EdgeBackGesture(action: action))
    }
}
