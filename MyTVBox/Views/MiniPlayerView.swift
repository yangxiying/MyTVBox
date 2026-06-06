import SwiftUI
import UIKit

/// 底部迷你播放条
/// - 固定高度 60pt
/// - 顶部细进度条
/// - 左侧封面 + 标题，右侧播放/暂停 + 关闭
/// - 点击非按钮区域展开全屏 AudioPlayerView
struct MiniPlayerView: View {

    @ObservedObject private var manager = AudioPlayerManager.shared
    @State private var showFullPlayer = false

    var progress: Double {
        guard manager.duration > 0 else { return 0 }
        return min(1.0, max(0, manager.currentTime / manager.duration))
    }

    var body: some View {
        if manager.isActive, manager.currentEpisode != nil {
            content
                .fullScreenCover(isPresented: $showFullPlayer) {
                    AudioPlayerView()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // 顶部细进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: geo.size.width * CGFloat(progress))
                }
            }
            .frame(height: 2)

            HStack(spacing: 12) {
                // 封面（点击区）
                artwork
                    .padding(.leading, 12)

                // 标题（点击区）
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.displayTitle.isEmpty ? "未播放" : manager.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(subtitleText)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    showFullPlayer = true
                }

                // 播放 / 暂停
                Button {
                    manager.toggle()
                } label: {
                    Image(systemName: manager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle().fill(Color.white.opacity(0.10))
                        )
                }
                .buttonStyle(.plain)

                // 关闭
                Button {
                    manager.cleanup()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
            .frame(height: 58)
        }
        .frame(height: 60)
        .background(
            ZStack {
                Color(red: 0.10, green: 0.08, blue: 0.18)
                LinearGradient(
                    colors: [Color.white.opacity(0.04), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5),
                alignment: .top
            )
        )
        .onTapGesture {
            // 点击空白区域展开
            showFullPlayer = true
        }
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
            if let img = manager.displayArtwork {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            showFullPlayer = true
        }
    }

    private var subtitleText: String {
        if !manager.playlist.isEmpty {
            let pos = "\(manager.currentEpisodeIndex + 1)/\(manager.playlist.count)"
            return "\(pos) · \(manager.playMode.rawValue)"
        }
        return manager.playMode.rawValue
    }
}

#if DEBUG
#if compiler(>=5.9)
@available(iOS 17, *)
struct Preview_MiniPlayerView: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            MiniPlayerView()
        }
        .background(Color.gray)
    }
}
#endif

#endif
