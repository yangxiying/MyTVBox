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
        VStack(spacing: 16) {
            GeometryReader { geo in
                let totalHSpacing = columnSpacing * CGFloat(columns - 1)
                let cardWidth = (geo.size.width - totalHSpacing) / CGFloat(columns)
                let rows = stride(from: 0, to: items.count, by: columns).map {
                    Array(items[$0..<min($0 + columns, items.count)])
                }
                VStack(spacing: rowSpacing) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, rowItems in
                        HStack(alignment: .top, spacing: columnSpacing) {
                            ForEach(Array(rowItems.enumerated()), id: \.element.id) { colIdx, item in
                                let globalIdx = rowIdx * columns + colIdx
                                Button {
                                    onItemTap(item)
                                } label: {
                                    VideoCardView(item: item, index: globalIdx + 1)
                                }
                                .buttonStyle(CardPressStyle())
                                .frame(width: cardWidth)
                                .onAppear {
                                    let triggerIndex = max(0, items.count - 4)
                                    if globalIdx >= triggerIndex {
                                        onLoadMore()
                                    }
                                }
                            }
                            // 奇数个 item 时右侧补空位保持列宽一致
                            if rowItems.count < columns {
                                ForEach(0..<(columns - rowItems.count), id: \.self) { _ in
                                    Color.clear.frame(width: cardWidth)
                                }
                            }
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
