import SwiftUI

/// 可复用的内容网格 —— 固定 2 列；底部支持加载更多指示器
/// - 倒数第 4 个 item 出现时触发 onLoadMore（避免到底再触发的延迟感）
struct ContentGridView: View {

    let items: [VideoItem]
    let isLoadingMore: Bool
    let onLoadMore: () -> Void
    let onItemTap: (VideoItem) -> Void

    private let columns = 2
    private let columnSpacing: CGFloat = 14
    private let rowSpacing: CGFloat = 18

    var body: some View {
        // GeometryReader 只用于测量父级宽度，不占高度
        VStack(spacing: 0) {
            GeometryReader { proxy in
                Color.clear
                    .preference(key: GridWidthKey.self, value: proxy.size.width)
            }
            .frame(height: 0)

            if let width = gridWidth {
                let totalSpacing = columnSpacing * CGFloat(columns - 1)
                let cardWidth = (width - totalSpacing - 32) / CGFloat(columns)  // 32 = horizontal padding

                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: columnSpacing), count: columns),
                    spacing: rowSpacing
                ) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        Button {
                            onItemTap(item)
                        } label: {
                            VideoCardView(item: item, index: idx + 1)
                        }
                        .buttonStyle(CardPressStyle())
                        .onAppear {
                            let triggerIndex = max(0, items.count - 4)
                            if idx >= triggerIndex { onLoadMore() }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

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
        .onPreferenceChange(GridWidthKey.self) { gridWidth = $0 }
    }

    @State private var gridWidth: CGFloat?
}

private struct GridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let v = nextValue()
        if v > 0 { value = v }
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
