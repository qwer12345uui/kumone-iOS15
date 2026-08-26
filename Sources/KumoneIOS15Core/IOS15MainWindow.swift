import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import UIKit

/// A self-contained iOS 15 baseline client. It deliberately uses only APIs that
/// are available on iOS 15, while retaining the same NetEase API transport and
/// models as the desktop client.
@MainActor
public struct IOS15MainWindow: View {
    @StateObject private var store: IOS15MusicStore
    @StateObject private var account = IOS15AccountStore()
    @State private var selectedTab = IOS15Tab.home
    @State private var selectionFeedback = UISelectionFeedbackGenerator()

    public init() {
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        let installPreview = arguments.contains("-KumonePlayerPreview")
            || environment["KUMONE_UI_TEST_PREVIEW_TRACK"] == "1"
        _store = StateObject(wrappedValue: IOS15MusicStore(installingUITestPreview: installPreview))
        // The standard tab bar is replaced by an accessible SwiftUI bar below.
        // Hiding it at appearance time retains TabView's content switching while
        // avoiding a second navigation layer behind the floating glass container.
        UITabBar.appearance().isHidden = true
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            IOS15HomeTab(store: store, account: account)
                .tag(IOS15Tab.home)

            IOS15DiscoverTab(store: store)
                .tag(IOS15Tab.explore)

            IOS15FMTab(store: store)
                .tag(IOS15Tab.fm)

            IOS15SearchTab(store: store)
                .tag(IOS15Tab.search)

            IOS15ProfileTab(store: store, account: account)
                .tag(IOS15Tab.profile)
        }
        // The bar is inserted first; the outer mini-player inset then reserves
        // the physical bottom edge, so navigation consistently sits above the
        // player and remains tappable on every tab.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            IOS15GlassTabBar(selection: $selectedTab)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            IOS15MiniPlayer(store: store)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .onAppear {
            selectionFeedback.prepare()
        }
        .onChange(of: selectedTab) { _ in
            selectionFeedback.selectionChanged()
            selectionFeedback.prepare()
        }
        .animation(
            .spring(response: 0.28, dampingFraction: 0.86, blendDuration: 0),
            value: selectedTab
        )
        .animation(
            .spring(response: 0.28, dampingFraction: 0.9, blendDuration: 0),
            value: store.currentTrack?.id
        )
        .tint(Color(red: 0.78, green: 0.12, blue: 0.18))
        .alert(
            "播放提示",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.dismissError() } }
            )
        ) {
            Button("好", role: .cancel) {
                store.dismissError()
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

private enum IOS15Tab: CaseIterable, Hashable {
    case home
    case explore
    case fm
    case search
    case profile

    var title: String {
        switch self {
        case .home: return "推荐"
        case .explore: return "精选"
        case .fm: return "漫游"
        case .search: return "搜索"
        case .profile: return "我的"
        }
    }

    var symbolName: String {
        switch self {
        case .home: return "house.fill"
        case .explore: return "square.grid.2x2.fill"
        case .fm: return "wave.3.right.circle.fill"
        case .search: return "magnifyingglass"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

private struct IOS15GlassTabBar: View {
    @Binding var selection: IOS15Tab
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        glassContainer
            .accessibilityElement(children: .contain)
    }

    private var glassContainer: some View {
        Group {
            if #available(iOS 26.0, *) {
                tabItems
                    .glassEffect(.regular.interactive(), in: Capsule())
            } else {
                tabItems
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(fallbackBorderColor, lineWidth: 1))
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.14), radius: 18, y: 8)
            }
        }
    }

    private var tabItems: some View {
        HStack(spacing: 0) {
            ForEach(IOS15Tab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 23, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(selection == tab ? Color.pink : inactiveForeground)
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .background {
                        if selection == tab {
                            Capsule(style: .continuous)
                                .fill(selectedFill)
                                .padding(4)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(4)
    }

    private var selectedFill: Color {
        colorScheme == .dark
            ? Color.pink.opacity(0.34)
            : Color.pink.opacity(0.18)
    }

    private var inactiveForeground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.92)
            : Color.black.opacity(0.88)
    }

    private var fallbackBorderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.white.opacity(0.72)
    }
}

enum IOS15PlaybackMode: String, CaseIterable {
    case sequential
    case shuffle
    case repeatOne

    var symbolName: String {
        switch self {
        case .sequential: return "text.line.first.and.arrowtriangle.forward"
        case .shuffle: return "shuffle"
        case .repeatOne: return "repeat.1"
        }
    }

    var title: String {
        switch self {
        case .sequential: return "顺序播放"
        case .shuffle: return "随机播放"
        case .repeatOne: return "单曲循环"
        }
    }

    var next: IOS15PlaybackMode {
        switch self {
        case .sequential: return .shuffle
        case .shuffle: return .repeatOne
        case .repeatOne: return .sequential
        }
    }
}

@MainActor
final class IOS15MusicStore: ObservableObject {
    @Published private(set) var recommendations: [PlaylistSummary] = []
    @Published private(set) var discovery: [PlaylistSummary] = []
    @Published private(set) var fmTracks: [Track] = []
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isLoadingRecommendations = false
    @Published private(set) var isLoadingDiscovery = false
    @Published private(set) var isLoadingFM = false
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var isPreparingPlayback = false
    @Published private(set) var playbackTime: TimeInterval = 0
    @Published private(set) var playbackMode: IOS15PlaybackMode = .sequential
    @Published private(set) var playbackRate: Float = 1.0
    @Published private(set) var playHistory: [Track] = []
    @Published private(set) var playQueue: [Track] = []
    @Published private(set) var isMuted = false
    /// UI-only status for the active authorized resolver. The built-in resolver
    /// remains the default until an explicitly authorized provider is supplied.
    @Published private(set) var audioSourceStatus = "内置播放服务"

    private let playHistoryKey = "kumone.ios15.play-history.v1"
    private let playbackModeKey = "kumone.ios15.playback-mode.v1"
    private var player: AVPlayer?
    private var playerItemStatusObservation: NSKeyValueObservation?
    private var itemEndObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var remoteCommandsInstalled = false

    init(installingUITestPreview: Bool = false) {
        loadPlayHistory()
        loadPlaybackMode()
        if installingUITestPreview {
            installUITestPreviewTrack()
        }
    }

    private func installUITestPreviewTrack() {
        let fixture = """
        [
          {"id": -15001, "name": "播放器测试歌曲", "ar": [{"id": 1, "name": "Kumone"}], "al": {"id": 1, "name": "iOS 15 测试专辑", "picUrl": null}, "dt": 240000, "fee": 0, "mv": 0, "no": 1},
          {"id": -15002, "name": "队列测试歌曲", "ar": [{"id": 2, "name": "Kumone"}], "al": {"id": 2, "name": "iOS 15 测试专辑", "picUrl": null}, "dt": 180000, "fee": 0, "mv": 0, "no": 2}
        ]
        """
        guard let data = fixture.data(using: .utf8),
              let tracks = try? JSONDecoder().decode([Track].self, from: data),
              let current = tracks.first else { return }
        currentTrack = current
        playQueue = tracks
        playbackTime = 42
        audioSourceStatus = "测试内置音源"
    }

    func loadRecommendations(force: Bool = false) async {
        guard force || recommendations.isEmpty, !isLoadingRecommendations else { return }
        isLoadingRecommendations = true
        defer { isLoadingRecommendations = false }
        do {
            recommendations = try await NeteaseAPI.personalizedPlaylists(limit: 24)
        } catch {
            errorMessage = "推荐内容暂时无法加载，请稍后重试。"
        }
    }

    func loadDiscovery(force: Bool = false) async {
        guard force || discovery.isEmpty, !isLoadingDiscovery else { return }
        isLoadingDiscovery = true
        defer { isLoadingDiscovery = false }
        do {
            discovery = (try await NeteaseAPI.topPlaylists(category: "全部", limit: 30)).playlists
        } catch {
            errorMessage = "精选内容暂时无法加载，请稍后重试。"
        }
    }

    func loadFM(force: Bool = false) async {
        guard force || fmTracks.isEmpty, !isLoadingFM else { return }
        isLoadingFM = true
        defer { isLoadingFM = false }
        do {
            fmTracks = try await NeteaseAPI.personalFM()
        } catch {
            errorMessage = "漫游电台暂时无法加载，请登录后重试。"
        }
    }

    func playFM(_ track: Track) async {
        setPlayQueue(from: fmTracks, selecting: track)
        await startPlayback(track)
    }

    func trashFM(_ track: Track) async {
        do {
            try await NeteaseAPI.fmTrash(id: track.id)
        } catch {
            // The server may reject a skip for anonymous sessions. Keep the
            // local queue usable and surface the standard network message only
            // when the replacement request also fails.
        }
        fmTracks.removeAll { $0.id == track.id }
        if fmTracks.count < 3 {
            do {
                let replacement = try await NeteaseAPI.personalFM()
                var known = Set(fmTracks.map(\.id))
                fmTracks.append(contentsOf: replacement.filter { known.insert($0.id).inserted })
            } catch {
                errorMessage = "无法获取新的漫游歌曲，请检查登录状态或网络。"
            }
        }
        if currentTrack?.id == track.id {
            if let next = fmTracks.first {
                await playFM(next)
            } else {
                dismissCurrentTrack()
            }
        }
    }

    func loadPlaylist(_ playlist: PlaylistSummary) async {
        errorMessage = nil
        do {
            let detail = try await NeteaseAPI.playlistDetail(id: playlist.id).playlist
            if detail.tracks.isEmpty, !detail.trackIds.isEmpty {
                tracks = try await NeteaseAPI.songDetails(ids: detail.trackIds.map(\.id)).songs
            } else {
                tracks = detail.tracks
            }
        } catch {
            errorMessage = "歌单加载失败，请稍后重试。"
        }
    }

    func search(_ keywords: String) async {
        let term = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !isSearching else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            tracks = (try await NeteaseAPI.search(term, type: .songs, limit: 50)).songs ?? []
        } catch {
            errorMessage = "未能完成搜索，请检查网络后重试。"
        }
    }

    func play(_ track: Track) async {
        setPlayQueue(from: tracks, selecting: track)
        await startPlayback(track)
    }

    private func startPlayback(_ track: Track) async {
        currentTrack = track
        errorMessage = nil
        isPlaying = false
        isPreparingPlayback = true

        let url: URL
        do {
            let stream = try await NeteaseAPI.songURL(ids: [track.id], level: "standard").first
            guard let rawURL = stream?.url, let resolvedURL = URL(string: rawURL) else {
                errorMessage = "播放地址响应中没有可用音频流。"
                isPreparingPlayback = false
                return
            }
            url = resolvedURL
        } catch {
            errorMessage = "播放地址请求失败：\(error.localizedDescription)"
            isPreparingPlayback = false
            return
        }

        // Foreground playback must not be blocked by an optional session policy.
        // Some iOS 15 devices return the generic 'what' OSStatus for explicit
        // session activation even though AVPlayer can still start normally.
        configurePlaybackSessionIfPossible()

        player?.pause()
        removePlaybackTimeObserver()
        playerItemStatusObservation?.invalidate()
        playbackTime = 0
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true
        player.isMuted = isMuted
        self.player = player
        installPlaybackTimeObserver(on: player)
        installItemEndObserver(for: item)
        observePlaybackReadiness(item, track: track)
        installRemoteCommandsIfNeeded()
    }

    private func installPlaybackTimeObserver(on player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard time.seconds.isFinite else { return }
            Task { @MainActor [weak self] in
                self?.playbackTime = max(0, time.seconds)
            }
        }
    }

    private func removePlaybackTimeObserver() {
        guard let observer = timeObserver else { return }
        player?.removeTimeObserver(observer)
        timeObserver = nil
    }

    private func installItemEndObserver(for item: AVPlayerItem) {
        if let observer = itemEndObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handlePlaybackFinished()
            }
        }
    }

    private func observePlaybackReadiness(_ item: AVPlayerItem, track: Track) {
        playerItemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.handlePlaybackItemStatus(item, track: track)
            }
        }
        Task { @MainActor [weak self, weak item] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, let item, item === self.player?.currentItem,
                  item.status == .unknown else { return }
            self.isPreparingPlayback = false
            self.errorMessage = "音频流 15 秒内未就绪。请确认网络可访问网易云 CDN，然后重试。"
        }
    }

    private func handlePlaybackItemStatus(_ item: AVPlayerItem, track: Track) {
        guard item === player?.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            guard !isPlaying else { return }
            isPreparingPlayback = false
            player?.playImmediately(atRate: playbackRate)
            isPlaying = true
            recordPlayback(of: track)
            publishNowPlayingInfo(for: track)
        case .failed:
            isPlaying = false
            isPreparingPlayback = false
            let reason = item.error?.localizedDescription ?? "服务器拒绝了该音频流。"
            errorMessage = "音频流加载失败：\(reason)"
            refreshNowPlayingPlaybackState()
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func setPlayQueue(from source: [Track], selecting track: Track) {
        var seen = Set<Int>()
        let normalized = source.filter { seen.insert($0.id).inserted }
        playQueue = normalized.contains(where: { $0.id == track.id }) ? normalized : [track]
    }

    func playPrevious() {
        guard !isPreparingPlayback, let currentTrack else { return }
        guard let index = playQueue.firstIndex(where: { $0.id == currentTrack.id }), index > 0 else {
            playbackTime = 0
            player?.seek(to: .zero)
            resumePlayback()
            return
        }
        Task { await startPlayback(playQueue[index - 1]) }
    }

    func playNext() {
        guard !isPreparingPlayback, let currentTrack, !playQueue.isEmpty else { return }
        let nextTrack: Track?
        if playbackMode == .shuffle {
            let alternatives = playQueue.filter { $0.id != currentTrack.id }
            nextTrack = alternatives.randomElement() ?? currentTrack
        } else if let index = playQueue.firstIndex(where: { $0.id == currentTrack.id }),
                  index + 1 < playQueue.count {
            nextTrack = playQueue[index + 1]
        } else {
            nextTrack = nil
        }
        guard let nextTrack else { return }
        Task { await startPlayback(nextTrack) }
    }

    func selectQueuedTrack(_ track: Track) {
        guard !isPreparingPlayback else { return }
        Task { await startPlayback(track) }
    }

    func toggleMuted() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    func cyclePlaybackRate() {
        let rates: [Float] = [1.0, 1.25, 1.5, 2.0]
        let index = rates.firstIndex(where: { abs($0 - playbackRate) < 0.01 }) ?? 0
        playbackRate = rates[(index + 1) % rates.count]
        if isPlaying {
            player?.rate = playbackRate
        }
        refreshNowPlayingPlaybackState()
    }

    var playbackRateLabel: String {
        let text = String(format: "%.2f", playbackRate)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        return "\(text)×"
    }

    private func handlePlaybackFinished() {
        guard let currentTrack else { return }
        switch playbackMode {
        case .repeatOne:
            playbackTime = 0
            player?.seek(to: .zero)
            player?.playImmediately(atRate: playbackRate)
            isPlaying = true
            refreshNowPlayingPlaybackState()
        case .sequential:
            guard let index = playQueue.firstIndex(where: { $0.id == currentTrack.id }),
                  index + 1 < playQueue.count else {
                isPlaying = false
                refreshNowPlayingPlaybackState()
                return
            }
            Task { await startPlayback(playQueue[index + 1]) }
        case .shuffle:
            guard !playQueue.isEmpty else {
                isPlaying = false
                refreshNowPlayingPlaybackState()
                return
            }
            let alternatives = playQueue.filter { $0.id != currentTrack.id }
            let next = alternatives.randomElement() ?? currentTrack
            Task { await startPlayback(next) }
        }
    }

    func cyclePlaybackMode() {
        playbackMode = playbackMode.next
        UserDefaults.standard.set(playbackMode.rawValue, forKey: playbackModeKey)
    }

    /// Compact-player mode button: deliberately toggles only the two requested
    /// automatic modes, random play and repeat-one.
    func toggleShuffleOrRepeatOne() {
        playbackMode = playbackMode == .shuffle ? .repeatOne : .shuffle
        UserDefaults.standard.set(playbackMode.rawValue, forKey: playbackModeKey)
    }

    private func loadPlaybackMode() {
        guard let rawValue = UserDefaults.standard.string(forKey: playbackModeKey),
              let mode = IOS15PlaybackMode(rawValue: rawValue) else { return }
        playbackMode = mode
    }

    func clearPlayHistory() {
        playHistory = []
        UserDefaults.standard.removeObject(forKey: playHistoryKey)
    }

    private func loadPlayHistory() {
        guard let data = UserDefaults.standard.data(forKey: playHistoryKey),
              let tracks = try? JSONDecoder().decode([Track].self, from: data)
        else { return }
        playHistory = tracks
    }

    private func recordPlayback(of track: Track) {
        playHistory.removeAll { $0.id == track.id }
        playHistory.insert(track, at: 0)
        if playHistory.count > 100 {
            playHistory.removeLast(playHistory.count - 100)
        }
        if let data = try? JSONEncoder().encode(playHistory) {
            UserDefaults.standard.set(data, forKey: playHistoryKey)
        }
    }

    /// Attempts to prepare background-capable audio, but deliberately never
    /// blocks foreground playback when a device rejects explicit session changes.
    private func configurePlaybackSessionIfPossible() {
        let session = AVAudioSession.sharedInstance()
        // Avoid optional policies and route-specific options. On iOS 15 the
        // default AVPlayer session is sufficient for foreground playback.
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func installRemoteCommandsIfNeeded() {
        guard !remoteCommandsInstalled else { return }
        remoteCommandsInstalled = true

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.resumePlayback() }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.pausePlayback() }
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.togglePlayback() }
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.playNext() }
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.playPrevious() }
            return .success
        }
    }

    private func resumePlayback() {
        guard let player else { return }
        player.playImmediately(atRate: playbackRate)
        isPlaying = true
        refreshNowPlayingPlaybackState()
    }

    private func pausePlayback() {
        guard let player else { return }
        player.pause()
        isPlaying = false
        refreshNowPlayingPlaybackState()
    }

    private func publishNowPlayingInfo(for track: Track) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.artistNames,
            MPMediaItemPropertyAlbumTitle: track.album.name,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0.0
        ]
        let seconds = player?.currentTime().seconds ?? 0
        if seconds.isFinite { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func refreshNowPlayingPlaybackState() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        publishNowPlayingInfo(for: track)
    }

    func togglePlayback() {
        guard !isPreparingPlayback else { return }
        if isPlaying {
            pausePlayback()
        } else {
            resumePlayback()
        }
    }

    func seek(to seconds: TimeInterval) {
        guard let player, seconds.isFinite else { return }
        let clamped = max(0, min(seconds, currentTrack?.duration ?? seconds))
        playbackTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        refreshNowPlayingPlaybackState()
    }

    func dismissCurrentTrack() {
        player?.pause()
        removePlaybackTimeObserver()
        playerItemStatusObservation?.invalidate()
        playerItemStatusObservation = nil
        if let observer = itemEndObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        itemEndObserver = nil
        player = nil
        currentTrack = nil
        isPlaying = false
        isPreparingPlayback = false
        isMuted = false
        playbackTime = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private struct IOS15HomeTab: View {
    @ObservedObject var store: IOS15MusicStore
    @ObservedObject var account: IOS15AccountStore
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            playlistList(
                title: "推荐",
                emptyTitle: "正在加载推荐内容",
                playlists: store.recommendations,
                isLoading: store.isLoadingRecommendations
            )
            .navigationBarTitle("推荐", displayMode: .large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await store.loadRecommendations(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新推荐")
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showSettings) {
            IOS15SettingsView(account: account)
        }
        .task {
            await store.loadRecommendations()
        }
    }

    @ViewBuilder
    private func playlistList(
        title: String,
        emptyTitle: String,
        playlists: [PlaylistSummary],
        isLoading: Bool
    ) -> some View {
        if playlists.isEmpty {
            VStack(spacing: 14) {
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary)
                }
                Text(emptyTitle)
                    .foregroundColor(.secondary)
            }
        } else {
            List(playlists) { playlist in
                NavigationLink(destination: IOS15PlaylistDetail(store: store, playlist: playlist)) {
                    IOS15PlaylistRow(playlist: playlist)
                }
            }
            .listStyle(InsetGroupedListStyle())
        }
    }
}

private struct IOS15DiscoverTab: View {
    @ObservedObject var store: IOS15MusicStore

    var body: some View {
        NavigationView {
            Group {
                if store.discovery.isEmpty {
                    VStack(spacing: 14) {
                        if store.isLoadingDiscovery {
                            ProgressView()
                        } else {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 34))
                                .foregroundColor(.secondary)
                        }
                        Text("正在加载精选歌单")
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(store.discovery) { playlist in
                        NavigationLink(destination: IOS15PlaylistDetail(store: store, playlist: playlist)) {
                            IOS15PlaylistRow(playlist: playlist)
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationBarTitle("精选", displayMode: .large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await store.loadDiscovery(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新精选")
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .task {
            await store.loadDiscovery()
        }
    }
}

private struct IOS15FMTab: View {
    @ObservedObject var store: IOS15MusicStore

    var body: some View {
        NavigationView {
            Group {
                if store.fmTracks.isEmpty {
                    VStack(spacing: 14) {
                        if store.isLoadingFM {
                            ProgressView()
                        } else {
                            Image(systemName: "wave.3.right.circle")
                                .font(.system(size: 38))
                                .foregroundColor(.secondary)
                        }
                        Text("正在加载漫游电台")
                            .foregroundColor(.secondary)
                        if !store.isLoadingFM {
                            Button("重新加载") {
                                Task { await store.loadFM(force: true) }
                            }
                        }
                    }
                } else {
                    List(store.fmTracks) { track in
                        HStack(spacing: 4) {
                            Button {
                                Task { await store.playFM(track) }
                            } label: {
                                IOS15TrackRow(track: track, isCurrent: store.currentTrack?.id == track.id)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button {
                                Task { await store.trashFM(track) }
                            } label: {
                                Image(systemName: "forward.fill")
                                    .foregroundColor(.secondary)
                                    .frame(width: 34, height: 38)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel("不喜欢并跳过 \(track.name)")
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationBarTitle("漫游", displayMode: .large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await store.loadFM(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新漫游电台")
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .task {
            await store.loadFM()
        }
    }
}

private struct IOS15SearchTab: View {
    @ObservedObject var store: IOS15MusicStore
    @State private var keywords = ""
    @State private var hasSearched = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Text("搜索")
                    .font(.system(size: 38, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 26)
                    .padding(.bottom, 14)

                HStack(spacing: 10) {
                    TextField("搜索歌曲、歌手", text: $keywords, onCommit: search)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .submitLabel(.search)
                    Button("搜索", action: search)
                        .disabled(keywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()

                if store.isSearching {
                    Spacer()
                    ProgressView("正在搜索")
                    Spacer()
                } else if !hasSearched {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary)
                    Text("输入关键词开始搜索")
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                } else if store.tracks.isEmpty {
                    Spacer()
                    Text("没有找到匹配歌曲")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    List(store.tracks) { track in
                        Button {
                            Task { await store.play(track) }
                        } label: {
                            IOS15TrackRow(track: track, isCurrent: store.currentTrack?.id == track.id)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .listStyle(PlainListStyle())
                }
            }
            // The content title is intentional: the system navigation bar stays
            // hidden so it never reserves vertical space above search results.
            .navigationBarHidden(true)
            .animation(.spring(response: 0.28, dampingFraction: 0.9), value: store.currentTrack?.id)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func search() {
        hasSearched = true
        Task { await store.search(keywords) }
    }
}

private struct IOS15PlaylistDetail: View {
    @ObservedObject var store: IOS15MusicStore
    let playlist: PlaylistSummary

    var body: some View {
        Group {
            if store.tracks.isEmpty {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("正在加载歌曲")
                        .foregroundColor(.secondary)
                }
            } else {
                List(store.tracks) { track in
                    Button {
                        Task { await store.play(track) }
                    } label: {
                        IOS15TrackRow(track: track, isCurrent: store.currentTrack?.id == track.id)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationBarTitle(playlist.name, displayMode: .inline)
        .task {
            await store.loadPlaylist(playlist)
        }
    }
}

private struct IOS15PlaylistRow: View {
    let playlist: PlaylistSummary

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: playlist.coverURL?.resizedImageURL(120)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.16)
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(playlist.copywriter ?? "歌单")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

struct IOS15TrackRow: View {
    let track: Track
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCurrent ? "speaker.wave.2.fill" : "music.note")
                .foregroundColor(isCurrent ? .red : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.name)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(track.artistNames) · \(track.album.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle")
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
    }
}

private struct IOS15LegacyMiniPlayer: View {
    @ObservedObject var store: IOS15MusicStore
    @State private var lyricsTrack: Track?

    var body: some View {
        if let track = store.currentTrack {
            HStack(spacing: 8) {
                miniControl(
                    symbol: store.playbackMode == .repeatOne ? "repeat.1" : "shuffle",
                    label: "播放模式：\(store.playbackMode.title)",
                    action: store.toggleShuffleOrRepeatOne
                )

                Button {
                    lyricsTrack = track
                } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: track.album.picUrl?.resizedImageURL(96)) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.secondary.opacity(0.16)
                        }
                        .frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(track.artistNames)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("显示歌词")
                Spacer(minLength: 2)
                miniControl(symbol: "backward.end.fill", label: "上一曲", action: store.playPrevious)
                if store.isPreparingPlayback {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .frame(width: 28, height: 30)
                        .accessibilityLabel("正在加载音频流")
                } else {
                    miniControl(
                        symbol: store.isPlaying ? "pause.fill" : "play.fill",
                        label: store.isPlaying ? "暂停" : "播放",
                        action: store.togglePlayback
                    )
                }

                miniControl(symbol: "forward.end.fill", label: "下一曲", action: store.playNext)
                Button(action: store.cyclePlaybackRate) {
                    Text(store.playbackRateLabel)
                        .font(.caption2.weight(.bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("播放倍速：\(store.playbackRateLabel)")

                Button(action: store.dismissCurrentTrack) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 34)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("关闭迷你播放器")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial)
            .overlay(Divider(), alignment: .top)
            .sheet(item: $lyricsTrack) { track in
                IOS15LyricsSheet(track: track, store: store)
            }
        }
    }

    private func miniControl(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 30)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
    }
}
