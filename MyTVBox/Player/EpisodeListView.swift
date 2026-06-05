import SwiftUI

// MARK: - 集数列表（横向）— 用于播放器内 HUD

struct EpisodeListView: View {

    let episodes: [PlayURL]
    let currentIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(PlayerTheme.amber)
                    .frame(width: 3, height: 14)
                Text("EPISODES")
                    .font(PlayerTheme.mono(11, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(PlayerTheme.textHigh)
                Text("\(currentIndex + 1) / \(episodes.count)")
                    .font(PlayerTheme.mono(10, weight: .medium))
                    .foregroundColor(PlayerTheme.textLow)
                Spacer()
            }
            .padding(.horizontal, 18)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(episodes.enumerated()), id: \.offset) { idx, ep in
                            EpisodeChip(
                                index: idx,
                                name: ep.name,
                                isActive: idx == currentIndex
                            )
                            .id(idx)
                            .onTapGesture { onSelect(idx) }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(currentIndex, anchor: .center)
                        }
                    }
                }
                .onChange(of: currentIndex) { newValue in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [PlayerTheme.ink.opacity(0.0), PlayerTheme.ink.opacity(0.92)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }
}

private struct EpisodeChip: View {
    let index: Int
    let name: String
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(String(format: "%02d", index + 1))
                    .font(PlayerTheme.mono(10, weight: .heavy))
                    .foregroundColor(isActive ? PlayerTheme.ink : PlayerTheme.amber)
                if isActive {
                    Image(systemName: "waveform")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(PlayerTheme.ink)
                }
            }
            Text(name)
                .font(PlayerTheme.sans(13, weight: isActive ? .heavy : .medium))
                .foregroundColor(isActive ? PlayerTheme.ink : PlayerTheme.textHigh)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 86)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? PlayerTheme.amber : PlayerTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isActive ? PlayerTheme.amber : PlayerTheme.hairline, lineWidth: 1)
                )
                .shadow(color: isActive ? PlayerTheme.amber.opacity(0.4) : .clear, radius: 8, x: 0, y: 2)
        )
        .animation(.easeOut(duration: 0.18), value: isActive)
    }
}

// MARK: - 集数网格视图（用于详情页）

struct EpisodeGridView: View {

    let episodes: [PlayURL]
    let currentIndex: Int?
    let onSelect: (Int) -> Void

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(episodes.enumerated()), id: \.offset) { idx, ep in
                Button {
                    onSelect(idx)
                } label: {
                    Text(ep.name)
                        .font(PlayerTheme.sans(13, weight: idx == currentIndex ? .heavy : .medium))
                        .foregroundColor(idx == currentIndex ? PlayerTheme.ink : PlayerTheme.textHigh)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(idx == currentIndex ? PlayerTheme.amber : PlayerTheme.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(idx == currentIndex ? PlayerTheme.amber : PlayerTheme.hairline, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
