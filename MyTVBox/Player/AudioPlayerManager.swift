import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import Combine

/// 音频播放管理器（单例）
/// - 全局唯一实例，App 生命周期内常驻
/// - 负责音频会话、AVPlayer 控制、远程命令、Now Playing、定时关闭
@MainActor
final class AudioPlayerManager: ObservableObject {

    // MARK: - 单例

    static let shared = AudioPlayerManager()

    // MARK: - Published 状态

    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var currentEpisode: PlayURL?
    @Published var currentEpisodeIndex: Int = 0
    @Published var playlist: [PlayURL] = []
    @Published var playMode: PlayMode = .sequential
    @Published var sleepTimerRemaining: TimeInterval? = nil
    @Published var sleepUntilTrackEnds: Bool = false

    /// 当前节目展示信息（用于 MiniPlayer / 锁屏）
    @Published var displayTitle: String = ""
    @Published var displayArtist: String? = nil
    @Published var displayArtwork: UIImage? = nil

    /// 是否处于可见状态（用于 MiniPlayer 显隐）
    @Published var isActive: Bool = false

    // MARK: - 私有

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var sleepTimer: Timer?
    private var endObserver: NSObjectProtocol?
    private var remoteCommandsRegistered: Bool = false

    // MARK: - 播放模式

    enum PlayMode: String, CaseIterable {
        case sequential = "顺序播放"
        case loop       = "列表循环"
        case single     = "单曲循环"
        case shuffle    = "随机播放"

        var systemImage: String {
            switch self {
            case .sequential: return "arrow.right.to.line"
            case .loop:       return "repeat"
            case .single:     return "repeat.1"
            case .shuffle:    return "shuffle"
            }
        }
    }

    // MARK: - 初始化

    private init() {
        setupAudioSession()
        setupRemoteCommandCenter()
        setupNotifications()
    }

    // MARK: - 音频会话

    func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance()
                .setCategory(.playback, mode: .default, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[AudioPlayerManager] AudioSession setup failed: \(error)")
        }
    }

    // MARK: - 通知

    private func setupNotifications() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePlaybackEnd()
            }
        }
    }

    private func handlePlaybackEnd() {
        // "播完当前"模式：曲目结束后停止
        if sleepUntilTrackEnds {
            cancelSleepTimer()
            pause()
            return
        }
        switch playMode {
        case .single:
            seek(to: 0)
            player?.play()
            isPlaying = true
            updateNowPlayingPlaybackRate(1)
        case .sequential:
            if currentEpisodeIndex < playlist.count - 1 {
                next()
            } else {
                pause()
            }
        case .loop:
            next()
        case .shuffle:
            playRandom()
        }
    }

    // MARK: - 播放控制

    /// 加载并播放指定曲目（带播放列表）
    func play(episode: PlayURL, in playlist: [PlayURL]) {
        self.playlist = playlist
        if let idx = playlist.firstIndex(where: { $0.url == episode.url }) {
            self.currentEpisodeIndex = idx
        } else {
            self.currentEpisodeIndex = 0
        }
        loadAndPlay(episode: episode)
        self.isActive = true
    }

    /// 切换到列表中的指定下标
    func play(at index: Int) {
        guard index >= 0, index < playlist.count else { return }
        currentEpisodeIndex = index
        loadAndPlay(episode: playlist[index])
    }

    private func loadAndPlay(episode: PlayURL) {
        removeTimeObserver()
        currentEpisode = episode
        displayTitle = episode.name
        currentTime = 0
        duration = 0

        guard let url = URL(string: episode.url) else {
            print("[AudioPlayerManager] Invalid URL: \(episode.url)")
            return
        }
        let item = AVPlayerItem(url: url)
        if let p = player {
            p.replaceCurrentItem(with: item)
        } else {
            player = AVPlayer(playerItem: item)
        }
        addTimeObserver()
        player?.play()
        isPlaying = true

        // 异步加载时长
        Task { [weak self] in
            guard let self = self else { return }
            if let dur = try? await item.asset.load(.duration) {
                let secs = CMTimeGetSeconds(dur)
                if secs.isFinite, secs > 0 {
                    self.duration = secs
                    self.updateNowPlayingInfo(
                        title: self.displayTitle,
                        artist: self.displayArtist,
                        artwork: self.displayArtwork
                    )
                }
            }
        }
        updateNowPlayingInfo(
            title: displayTitle,
            artist: displayArtist,
            artwork: displayArtwork
        )
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self = self else { return }
                let t = CMTimeGetSeconds(time)
                if t.isFinite { self.currentTime = t }
                if let item = self.player?.currentItem {
                    let dur = CMTimeGetSeconds(item.duration)
                    if dur.isFinite, dur > 0 { self.duration = dur }
                }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.currentTime
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }

    private func removeTimeObserver() {
        if let obs = timeObserver {
            player?.removeTimeObserver(obs)
            timeObserver = nil
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlayingPlaybackRate(0)
    }

    func resume() {
        // 若 player 不存在但有当前曲目，重新加载
        if player == nil, let ep = currentEpisode {
            loadAndPlay(episode: ep)
            return
        }
        player?.play()
        isPlaying = true
        updateNowPlayingPlaybackRate(1)
    }

    func toggle() {
        isPlaying ? pause() : resume()
    }

    func next() {
        guard !playlist.isEmpty else { return }
        if playMode == .shuffle {
            playRandom()
            return
        }
        var idx = currentEpisodeIndex + 1
        if idx >= playlist.count {
            if playMode == .loop {
                idx = 0
            } else {
                // sequential / single：到末尾停止
                pause()
                return
            }
        }
        currentEpisodeIndex = idx
        loadAndPlay(episode: playlist[idx])
    }

    func previous() {
        guard !playlist.isEmpty else { return }
        if playMode == .shuffle {
            playRandom()
            return
        }
        var idx = currentEpisodeIndex - 1
        if idx < 0 {
            idx = (playMode == .loop) ? (playlist.count - 1) : 0
        }
        currentEpisodeIndex = idx
        loadAndPlay(episode: playlist[idx])
    }

    private func playRandom() {
        guard !playlist.isEmpty else { return }
        var idx = Int.random(in: 0..<playlist.count)
        if playlist.count > 1, idx == currentEpisodeIndex {
            idx = (idx + 1) % playlist.count
        }
        currentEpisodeIndex = idx
        loadAndPlay(episode: playlist[idx])
    }

    func seek(to time: Double) {
        let target = max(0, time)
        let cm = CMTime(seconds: target, preferredTimescale: 600)
        player?.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.currentTime = target
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = target
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }

    func skipForward(_ seconds: Double = 15) {
        let upper = duration > 0 ? duration : .greatestFiniteMagnitude
        seek(to: min(upper, currentTime + seconds))
    }

    func skipBackward(_ seconds: Double = 15) {
        seek(to: max(0, currentTime - seconds))
    }

    // MARK: - 播放模式

    func togglePlayMode() {
        let modes = PlayMode.allCases
        if let idx = modes.firstIndex(of: playMode) {
            playMode = modes[(idx + 1) % modes.count]
        }
    }

    // MARK: - 定时关闭

    /// 设定 N 分钟后停止播放
    func setSleepTimer(minutes: Int) {
        cancelSleepTimer()
        sleepUntilTrackEnds = false
        let total = TimeInterval(minutes * 60)
        sleepTimerRemaining = total

        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard let r = self.sleepTimerRemaining else { return }
                let nr = r - 1
                if nr <= 0 {
                    self.pause()
                    self.cancelSleepTimer()
                } else {
                    self.sleepTimerRemaining = nr
                }
            }
        }
    }

    /// 播完当前曲目后停止
    func setSleepUntilTrackEnds() {
        cancelSleepTimer()
        sleepUntilTrackEnds = true
        sleepTimerRemaining = nil
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerRemaining = nil
        sleepUntilTrackEnds = false
    }

    var hasSleepTimer: Bool {
        sleepTimerRemaining != nil || sleepUntilTrackEnds
    }

    // MARK: - 远程命令

    func setupRemoteCommandCenter() {
        guard !remoteCommandsRegistered else { return }
        remoteCommandsRegistered = true

        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: e.positionTime) }
            return .success
        }
        cc.skipForwardCommand.preferredIntervals = [15]
        cc.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipForward(15) }
            return .success
        }
        cc.skipBackwardCommand.preferredIntervals = [15]
        cc.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipBackward(15) }
            return .success
        }
    }

    // MARK: - Now Playing

    func updateNowPlayingInfo(title: String, artist: String?, artwork: UIImage?) {
        self.displayTitle  = title
        self.displayArtist = artist
        self.displayArtwork = artwork

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        if let a = artist {
            info[MPMediaItemPropertyArtist] = a
        }
        if let img = artwork {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackRate(_ rate: Float) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - 工具

    /// 格式化时间为 mm:ss 或 h:mm:ss
    static func formatTime(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "00:00" }
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - 生命周期

    func cleanup() {
        removeTimeObserver()
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerRemaining = nil
        sleepUntilTrackEnds = false

        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil

        playlist = []
        currentEpisode = nil
        currentEpisodeIndex = 0
        currentTime = 0
        duration = 0
        isPlaying = false
        isActive = false

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
