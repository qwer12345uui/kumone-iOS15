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

    private var progressTotal: TimeInterval {
        max(1, max(track.duration, originalLines.last?.time ?? 0))
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
                        VStack(spacing: 0) {
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

                            VStack(spacing: 5) {
                                ProgressView(
                                    value: min(max(0, store.playbackTime), progressTotal),
                                    total: progressTotal
                                )
                                .tint(.pink)
                                HStack {
                                    Text(timeText(store.playbackTime))
                                    Spacer()
                                    Text(timeText(progressTotal))
                                }
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(.thinMaterial)
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

    private func timeText(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }
        let totalSeconds = max(0, Int(time.rounded(.down)))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
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

    /// Parses NetEase LRC tags with any minute width, optional fractional seconds,
    /// `.` or `:` fraction separators, and more than one timestamp per text line.
    private static func lines(from raw: String?) -> [TimedLyricLine] {
        guard let raw, !raw.isEmpty else { return [] }
        let expression = try? NSRegularExpression(pattern: #"\[(\d+):(\d+)(?:[.:](\d+))?\]"#)
        guard let expression else { return [] }

        var lines: [TimedLyricLine] = []
        var index = 0
        for rawLine in raw.components(separatedBy: .newlines) {
            let source = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { continue }
            let sourceRange = NSRange(source.startIndex..., in: source)
            let matches = expression.matches(in: source, range: sourceRange)
            guard let finalMatch = matches.last else { continue }

            let textStart = finalMatch.range.location + finalMatch.range.length
            guard textStart <= sourceRange.upperBound,
                  let textRange = Range(NSRange(location: textStart,
                                                 length: sourceRange.upperBound - textStart), in: source)
            else { continue }
            let text = String(source[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            for match in matches {
                guard let minuteRange = Range(match.range(at: 1), in: source),
                      let secondRange = Range(match.range(at: 2), in: source),
                      let minutes = Double(source[minuteRange]),
                      let seconds = Double(source[secondRange])
                else { continue }

                var fraction = 0.0
                let fractionRange = match.range(at: 3)
                if fractionRange.location != NSNotFound,
                   let range = Range(fractionRange, in: source),
                   let value = Double(source[range]) {
                    fraction = value / pow(10, Double(source[range].count))
                }
                lines.append(TimedLyricLine(
                    id: index,
                    time: minutes * 60 + seconds + fraction,
                    text: text
                ))
                index += 1
            }
        }
        return lines.sorted { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
    }
}

private struct TimedLyricLine: Identifiable {
    let id: Int
    let time: TimeInterval
    let text: String

    var timestampKey: Int {
        Int((time * 100).rounded())
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
