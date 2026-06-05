import SwiftUI

/// 可复用的内容网格 —— 自适应 2 列；底部支持加载更多指示器
/// - 倒数第 4 个 item 出现时触发 onLoadMore（避免到底再触发的延迟感）
struct ContentGridView: View {

    let items: [VideoItem]
    let isLoadingMore: Bool
    let onLoadMore: () -> Void
    let onItemTap: (VideoItem) -> Void

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    Button {
                        onItemTap(item)
                    } label: {
                        VideoCardView(item: item, index: idx + 1)
                    }
                    .buttonStyle(CardPressStyle())
                    .onAppear {
                        // 触发位置：倒数第 4 个或最后一个
                        let triggerIndex = max(0, items.count - 4)
                        if idx >= triggerIndex {
                            onLoadMore()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)

            if isLoadingMore {
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(TVBoxTheme.accent)
                        .scaleEffect(0.8)
                    Text("// LOADING MORE")
                        .font(TVBoxTheme.mono(10, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(TVBoxTheme.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .transition(.opacity)
            }
        }
    }
}

/// 卡片按下动效：轻微缩放 + 提亮
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
