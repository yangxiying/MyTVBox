import SwiftUI

/// 音频播放列表
/// - 显示当前列表全部曲目，高亮当前播放
/// - 点击切换播放
/// - 顶部显示播放模式
struct AudioPlaylistView: View {

    @ObservedObject private var manager = AudioPlayerManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            handle
                .padding(.top, 8)

            header
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            modePills
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            Divider()
                .background(Color.white.opacity(0.08))

            if manager.playlist.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.08, blue: 0.18),
                    Color(red: 0.04, green: 0.04, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - 子视图

    private var handle: some View {
        Capsule()
            .fill(Color.white.opacity(0.25))
            .frame(width: 40, height: 4)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("播放列表")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                Text("共 \(manager.playlist.count) 首")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
        }
    }

    private var modePills: some View {
        HStack(spacing: 8) {
            ForEach(AudioPlayerManager.PlayMode.allCases, id: \.self) { mode in
                let isSelected = manager.playMode == mode
                Button {
                    manager.playMode = mode
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                        Text(mode.rawValue)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(isSelected ? Color(red: 0.10, green: 0.08, blue: 0.18) : .white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white : Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var listContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(manager.playlist.enumerated()), id: \.element.id) { idx, item in
                        playlistRow(index: idx, item: item)
                            .id(idx)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .onAppear {
                // 滚动到当前播放位置
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        proxy.scrollTo(manager.currentEpisodeIndex, anchor: .center)
                    }
                }
            }
        }
    }

    private func playlistRow(index: Int, item: PlayURL) -> some View {
        let isCurrent = index == manager.currentEpisodeIndex && manager.currentEpisode?.url == item.url

        return Button {
            manager.play(at: index)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isCurrent ? Color.white : Color.white.opacity(0.08))
                        .frame(width: 32, height: 32)
                    if isCurrent {
                        if manager.isPlaying {
                            Image(systemName: "waveform")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(red: 0.10, green: 0.08, blue: 0.18))
                        } else {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(red: 0.10, green: 0.08, blue: 0.18))
                        }
                    } else {
                        Text("\(index + 1)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body.weight(isCurrent ? .semibold : .regular))
                        .foregroundColor(isCurrent ? .white : .white.opacity(0.85))
                        .lineLimit(1)
                    Text(item.url)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isCurrent ? Color.white.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.white.opacity(0.3))
            Text("暂无播放列表")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview {
    AudioPlaylistView()
}
#endif
