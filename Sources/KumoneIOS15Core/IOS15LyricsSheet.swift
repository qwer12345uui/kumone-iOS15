import Foundation
import SwiftUI

struct IOS15LyricsSheet: View {
    let track: Track
    @ObservedObject var store: IOS15MusicStore
    @Environment(\.presentationMode) private var presentationMode

    @State private var originalLines: [TimedLyricLine] = []
    @State private var translatedByTimestamp: [Int: String] = [:]
    @State private var romajiByTimestamp: [Int: String] = [:]
    @State private var showQueue = false
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
                            HStack(spacing: 6) {
                                Image(systemName: "waveform.path.ecg")
                                Text("当前音源：\(store.audioSourceStatus)")
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 10)

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

                            VStack(spacing: 13) {
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

                                HStack(spacing: 30) {
                                    lyricControlButton(
                                        symbol: "backward.end.fill",
                                        label: "上一曲",
                                        action: store.playPrevious
                                    )
                                    lyricControlButton(
                                        symbol: store.isPlaying ? "pause.circle.fill" : "play.circle.fill",
                                        label: store.isPlaying ? "暂停" : "播放",
                                        emphasized: true,
                                        action: store.togglePlayback
                                    )
                                    lyricControlButton(
                                        symbol: "forward.end.fill",
                                        label: "下一曲",
                                        action: store.playNext
                                    )
                                    Button(action: store.cyclePlaybackRate) {
                                        Text(store.playbackRateLabel)
                                            .font(.title3.weight(.semibold))
                                            .frame(width: 42, height: 38)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .accessibilityLabel("播放倍速：\(store.playbackRateLabel)")
                                }
                                .foregroundColor(.primary)
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: store.toggleShuffleOrRepeatOne) {
                        Image(systemName: store.playbackMode == .repeatOne ? "repeat.1" : "shuffle")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("播放模式：\(store.playbackMode.title)")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showQueue = true
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("播放队列")

                        Button("完成") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .ios15EdgeBack {
            presentationMode.wrappedValue.dismiss()
        }
        .sheet(isPresented: $showQueue) {
            IOS15PlaybackQueueSheet(store: store)
        }
        .task {
            await loadLyrics()
        }
    }

    private func lyricControlButton(
        symbol: String,
        label: String,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: emphasized ? 32 : 19, weight: .semibold))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func lyricRow(_ line: TimedLyricLine, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let romaji = romajiByTimestamp[line.timestampKey], !romaji.isEmpty {
                Text(romaji)
                    .font(.caption.weight(.medium))
                    .foregroundColor(isActive ? .primary.opacity(0.72) : .secondary.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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

            var romaji: [Int: String] = [:]
            for line in Self.lines(from: response.romalrc?.lyric) {
                romaji[line.timestampKey] = line.text
            }
            if IOS15RomajiTranscriber.isJapanese(originals.map(\.text)) {
                for line in originals where romaji[line.timestampKey] == nil {
                    if let generated = IOS15RomajiTranscriber.transcribe(line.text) {
                        romaji[line.timestampKey] = generated
                    }
                }
            } else {
                romaji = [:]
            }
            romajiByTimestamp = romaji
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
