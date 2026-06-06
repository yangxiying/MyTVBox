import SwiftUI
import UIKit

/// 音频全屏播放器
struct AudioPlayerView: View {

    @ObservedObject private var manager = AudioPlayerManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showSleepTimer = false
    @State private var showPlaylist = false

    @State private var isDragging = false
    @State private var dragValue: Double = 0

    var body: some View {
        ZStack {
            backgroundView
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)
                artworkView
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                titleSection
                    .padding(.horizontal, 32)
                    .padding(.bottom, 8)
                progressSection
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
                controlsBar
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                Spacer(minLength: 8)
                bottomActionsBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
            .padding(.top, 8)
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showSleepTimer) {
            SleepTimerView()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showPlaylist) {
            AudioPlaylistView()
        }
    }

    // MARK: - 背景

    private var backgroundView: some View {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.08, blue: 0.18),
                Color(red: 0.04, green: 0.04, blue: 0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - 顶部栏

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            Spacer()
            VStack(spacing: 2) {
                Text("正在播放")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                Text(manager.playlist.isEmpty ? "" : "\(manager.currentEpisodeIndex + 1) / \(manager.playlist.count)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.45))
            }
            Spacer()
            Button {
                showPlaylist = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 封面

    private var artworkView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.25, blue: 0.55),
                            Color(red: 0.18, green: 0.12, blue: 0.32)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)

            if let img = manager.displayArtwork {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 96, weight: .light))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - 标题

    private var titleSection: some View {
        VStack(spacing: 6) {
            Text(manager.displayTitle.isEmpty ? "未播放" : manager.displayTitle)
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let artist = manager.displayArtist, !artist.isEmpty {
                Text(artist)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - 进度

    private var progressBinding: Binding<Double> {
        Binding(
            get: { isDragging ? dragValue : manager.currentTime },
            set: { dragValue = $0 }
        )
    }

    private var progressSection: some View {
        VStack(spacing: 10) {
            Slider(
                value: progressBinding,
                in: 0...max(manager.duration, 0.01),
                onEditingChanged: { editing in
                    if editing {
                        isDragging = true
                        dragValue = manager.currentTime
                    } else {
                        manager.seek(to: dragValue)
                        isDragging = false
                    }
                }
            )
            .tint(.white)
            HStack {
                Text(AudioPlayerManager.formatTime(isDragging ? dragValue : manager.currentTime))
                Spacer()
                Text(AudioPlayerManager.formatTime(manager.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(.white.opacity(0.6))
        }
    }

    // MARK: - 主控制栏

    private var controlsBar: some View {
        HStack(spacing: 0) {
            controlButton(systemName: "backward.end.fill", size: 26) {
                manager.previous()
            }
            Spacer()
            controlButton(systemName: "gobackward.15", size: 28) {
                manager.skipBackward(15)
            }
            Spacer()
            // 播放/暂停 - 主按钮
            Button {
                manager.toggle()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 76, height: 76)
                    Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.black)
                        .offset(x: manager.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            controlButton(systemName: "goforward.15", size: 28) {
                manager.skipForward(15)
            }
            Spacer()
            controlButton(systemName: "forward.end.fill", size: 26) {
                manager.next()
            }
        }
    }

    private func controlButton(systemName: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部辅助

    private var bottomActionsBar: some View {
        HStack(spacing: 12) {
            // 播放模式
            Button {
                manager.togglePlayMode()
            } label: {
                actionPill(
                    icon: manager.playMode.systemImage,
                    text: manager.playMode.rawValue
                )
            }
            // 定时关闭
            Button {
                showSleepTimer = true
            } label: {
                actionPill(
                    icon: "moon.zzz.fill",
                    text: sleepTimerText,
                    highlighted: manager.hasSleepTimer
                )
            }
            // 列表
            Button {
                showPlaylist = true
            } label: {
                actionPill(
                    icon: "list.bullet.rectangle",
                    text: "列表"
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var sleepTimerText: String {
        if manager.sleepUntilTrackEnds {
            return "播完停止"
        }
        if let r = manager.sleepTimerRemaining {
            return AudioPlayerManager.formatTime(r)
        }
        return "定时"
    }

    private func actionPill(icon: String, text: String, highlighted: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundColor(highlighted ? Color(red: 0.10, green: 0.08, blue: 0.18) : .white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(highlighted ? Color.white.opacity(0.95) : Color.white.opacity(0.10))
        )
    }
}

#if DEBUG
#if compiler(>=5.9)
@available(iOS 17, *)
struct Preview_AudioPlayerView: PreviewProvider {
    static var previews: some View {
        AudioPlayerView()
    }
}
#endif

#endif
