import Foundation
import SwiftUI

/// iOS 15 fallback player chrome. It uses Material, standard stacks and sheets
/// rather than post-iOS-15 navigation or presentation APIs.
struct IOS15MiniPlayer: View {
    @ObservedObject var store: IOS15MusicStore
    @State private var lyricsTrack: Track?
    @State private var showQueue = false
    @State private var showCompactControls = false
    @State private var isEditingProgress = false
    @State private var draftProgress = 0.0

    var body: some View {
        if let track = store.currentTrack {
            GeometryReader { proxy in
                if proxy.size.width >= 680 {
                    regularPlayer(for: track)
                } else {
                    compactPlayer(for: track)
                }
            }
            .frame(height: 90)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(playerBackground)
            .sheet(item: $lyricsTrack) { selectedTrack in
                IOS15LyricsSheet(track: selectedTrack, store: store)
            }
            .sheet(isPresented: $showQueue) {
                IOS15PlaybackQueueSheet(store: store)
            }
            .confirmationDialog("更多播放控制", isPresented: $showCompactControls, titleVisibility: .visible) {
                Button("上一曲") { store.playPrevious() }
                Button("切换播放模式（\(store.playbackMode.title)）") { store.cyclePlaybackMode() }
                Button("歌词") { lyricsTrack = track }
                Button("播放队列") { showQueue = true }
                Button(store.isMuted ? "取消静音" : "静音") { store.toggleMuted() }
                Button("关闭迷你播放器", role: .destructive) { store.dismissCurrentTrack() }
                Button("取消", role: .cancel) { }
            } message: {
                Text("当前音源：\(store.audioSourceStatus)")
            }
        }
    }

    private var playerBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.thinMaterial)
            .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)
    }

    @ViewBuilder
    private func regularPlayer(for track: Track) -> some View {
        HStack(spacing: 16) {
            trackIdentity(track)
                .frame(width: 250, alignment: .leading)

            VStack(spacing: 5) {
                playerTransport
                progressControl(for: track)
            }
            .frame(maxWidth: .infinity)

            trailingActions
                .frame(width: 154, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func compactPlayer(for track: Track) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                trackIdentity(track)
                    .frame(maxWidth: .infinity, alignment: .leading)

                playbackRateButton
                compactButton(symbol: "forward.end.fill", label: "下一曲", action: store.playNext)
                playPauseButton
                compactButton(symbol: "ellipsis", label: "更多播放控制") {
                    showCompactControls = true
                }
            }

            compactProgressControl(for: track)
        }
    }

    private func trackIdentity(_ track: Track) -> some View {
        Button {
            lyricsTrack = track
        } label: {
            HStack(spacing: 10) {
                AsyncImage(url: track.album.picUrl?.resizedImageURL(112)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(track.artistNames)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("歌词：\(track.name)")
    }

    private var playerTransport: some View {
        HStack(spacing: 16) {
            playbackModeButton
            compactButton(symbol: "backward.end.fill", label: "上一曲", action: store.playPrevious)
            playPauseButton
            compactButton(symbol: "forward.end.fill", label: "下一曲", action: store.playNext)
            playbackRateButton
        }
    }

    private var playbackModeButton: some View {
        compactButton(
            symbol: playbackModeSymbol,
            label: "播放模式：\(store.playbackMode.title)",
            action: store.cyclePlaybackMode
        )
    }

    private var playbackModeSymbol: String {
        switch store.playbackMode {
        case .shuffle:
            return "shuffle"
        case .repeatOne:
            return "repeat.1"
        default:
            return "repeat"
        }
    }

    private var playbackRateButton: some View {
        Button(action: store.cyclePlaybackRate) {
            Text(store.playbackRateLabel)
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .frame(width: 34, height: 32)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("播放倍速：\(store.playbackRateLabel)")
        .accessibilityIdentifier("ios15-player-rate")
    }

    @ViewBuilder
    private var playPauseButton: some View {
        if store.isPreparingPlayback {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .frame(width: 42, height: 42)
                .accessibilityLabel("正在加载音频流")
        } else {
            Button(action: store.togglePlayback) {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.red, in: Circle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(store.isPlaying ? "暂停" : "播放")
        }
    }

    private var trailingActions: some View {
        HStack(spacing: 8) {
            Button {
                lyricsTrack = store.currentTrack
            } label: {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("歌词")

            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("播放队列")

            Button(action: store.toggleMuted) {
                Image(systemName: store.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(store.isMuted ? "取消静音" : "静音")

            Button(action: store.dismissCurrentTrack) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 28, height: 32)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("关闭迷你播放器")
        }
    }

    private func progressControl(for track: Track) -> some View {
        let duration = max(1, track.duration)
        return VStack(spacing: 2) {
            scrubber(duration: duration)
            HStack {
                Text(timeText(isEditingProgress ? draftProgress : store.playbackTime))
                Spacer()
                Text(timeText(duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundColor(.secondary)
        }
    }

    private func compactProgressControl(for track: Track) -> some View {
        let duration = max(1, track.duration)
        return scrubber(duration: duration)
            .frame(height: 14)
    }

    private func scrubber(duration: TimeInterval) -> some View {
        Slider(
            value: Binding(
                get: { isEditingProgress ? draftProgress : store.playbackTime },
                set: { draftProgress = $0 }
            ),
            in: 0...duration,
            onEditingChanged: { editing in
                isEditingProgress = editing
                if editing {
                    draftProgress = store.playbackTime
                } else {
                    store.seek(to: draftProgress)
                }
            }
        )
        .tint(.red)
        .accessibilityLabel("播放进度")
    }

    private func compactButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
    }

    private func timeText(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let seconds = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct IOS15PlaybackQueueSheet: View {
    @ObservedObject var store: IOS15MusicStore
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            List {
                if let current = store.currentTrack {
                    Section(header: Text("正在播放")) {
                        queueRow(current, current: true)
                    }
                }

                Section(header: Text("即将播放")) {
                    ForEach(store.playQueue.filter { $0.id != store.currentTrack?.id }) { track in
                        queueRow(track, current: false)
                    }
                    if store.playQueue.isEmpty {
                        Text("播放队列为空")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationBarTitle("播放队列 \(store.playQueue.count) 首", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func queueRow(_ track: Track, current: Bool) -> some View {
        Button {
            store.selectQueuedTrack(track)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: current ? "speaker.wave.2.fill" : "music.note")
                    .foregroundColor(current ? .red : .secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.name)
                        .foregroundColor(current ? .red : .primary)
                        .lineLimit(1)
                    Text(track.artistNames)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(timeText(track.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(current ? "正在播放：\(track.name)" : "播放队列：\(track.name)")
    }

    private func timeText(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let seconds = max(0, Int(value.rounded(.down)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
