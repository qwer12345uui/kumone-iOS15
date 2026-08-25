import AVFoundation
import Combine
import SwiftUI
import UIKit

/// A self-contained iOS 15 baseline client. It deliberately uses only APIs that
/// are available on iOS 15, while retaining the same NetEase API transport and
/// models as the desktop client.
@MainActor
public struct IOS15MainWindow: View {
    @StateObject private var store = IOS15MusicStore()
    @State private var selectedTab = IOS15Tab.home
    @State private var selectionFeedback = UISelectionFeedbackGenerator()

    public init() {
        // Keep TabView's content switching and accessibility semantics while the
        // floating glass frame supplies the visible three-tab navigation.
        UITabBar.appearance().isHidden = true
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            IOS15HomeTab(store: store)
                .tabItem {
                    Label("推荐", systemImage: "house.fill")
                }
                .tag(IOS15Tab.home)

            IOS15DiscoverTab(store: store)
                .tabItem {
                    Label("精选", systemImage: "square.grid.2x2.fill")
                }
                .tag(IOS15Tab.discover)

            IOS15SearchTab(store: store)
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .tag(IOS15Tab.search)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            IOS15GlassTabBar(selection: $selectedTab)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)
        }
        // No custom drag gesture is installed, so page and list scrolling remain
        // owned by the original upstream content.
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
        .tint(Color(red: 0.78, green: 0.12, blue: 0.18))
    }
}

private enum IOS15Tab: CaseIterable, Hashable {
    case home
    case discover
    case search

    var title: String {
        switch self {
        case .home: return "推荐"
        case .discover: return "精选"
        case .search: return "搜索"
        }
    }

    var symbolName: String {
        switch self {
        case .home: return "house.fill"
        case .discover: return "square.grid.2x2.fill"
        case .search: return "magnifyingglass"
        }
    }
}

private struct IOS15GlassTabBar: View {
    @Binding var selection: IOS15Tab
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                tabItems
                    .glassEffect(.regular.interactive(), in: Capsule())
            } else {
                tabItems
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(fallbackBorderColor, lineWidth: 1))
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.14),
                        radius: 18,
                        y: 8
                    )
            }
        }
        .accessibilityElement(children: .contain)
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
        colorScheme == .dark ? Color.pink.opacity(0.34) : Color.pink.opacity(0.18)
    }

    private var inactiveForeground: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88)
    }

    private var fallbackBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.72)
    }
}

@MainActor
final class IOS15MusicStore: ObservableObject {
    @Published private(set) var recommendations: [PlaylistSummary] = []
    @Published private(set) var discovery: [PlaylistSummary] = []
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isLoadingRecommendations = false
    @Published private(set) var isLoadingDiscovery = false
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false

    private var player: AVPlayer?

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
            tracks = try await NeteaseAPI.search(term, type: .songs, limit: 50).songs ?? []
        } catch {
            errorMessage = "未能完成搜索，请检查网络后重试。"
        }
    }

    func play(_ track: Track) async {
        currentTrack = track
        errorMessage = nil
        do {
            let stream = try await NeteaseAPI.songURL(ids: [track.id], level: "standard").first
            guard let rawURL = stream?.url,
                  let url = URL(string: rawURL.replacingOccurrences(of: "http://", with: "https://")) else {
                errorMessage = "该歌曲当前无法播放。"
                isPlaying = false
                return
            }
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
            isPlaying = true
        } catch {
            errorMessage = "播放地址获取失败，请稍后重试。"
            isPlaying = false
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }
}

private struct IOS15HomeTab: View {
    @ObservedObject var store: IOS15MusicStore

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
                        Task { await store.loadRecommendations(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新推荐")
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
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

private struct IOS15SearchTab: View {
    @ObservedObject var store: IOS15MusicStore
    @State private var keywords = ""
    @State private var hasSearched = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
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
            .navigationBarTitle("搜索", displayMode: .large)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                IOS15MiniPlayer(store: store)
            }
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            IOS15MiniPlayer(store: store)
        }
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

private struct IOS15TrackRow: View {
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

private struct IOS15MiniPlayer: View {
    @ObservedObject var store: IOS15MusicStore

    var body: some View {
        if let track = store.currentTrack {
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
                Spacer(minLength: 0)
                Button(action: store.togglePlayback) {
                    Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(store.isPlaying ? "暂停" : "播放")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial)
            .overlay(Divider(), alignment: .top)
        }
    }
}
