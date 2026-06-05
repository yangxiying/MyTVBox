import SwiftUI

// MARK: - 全局主题

/// MyTVBox 的视觉主题：深色 + 电光青 + 终端等宽字体
/// 整体风格：胶片黑底 / 微光网格 / CRT 光晕
enum TVBoxTheme {

    // 颜色
    static let bg              = Color(red: 0.04, green: 0.05, blue: 0.07)   // #0A0D12
    static let surface         = Color(red: 0.07, green: 0.09, blue: 0.12)   // #121821
    static let surfaceRaised   = Color(red: 0.10, green: 0.13, blue: 0.17)   // #1A212C
    static let stroke          = Color.white.opacity(0.07)
    static let strokeStrong    = Color.white.opacity(0.14)
    static let textPrimary     = Color(white: 0.96)
    static let textSecondary   = Color.white.opacity(0.55)
    static let textMuted       = Color.white.opacity(0.35)

    /// 电光青 —— 主点缀色，象征"信号 / 接通"
    static let accent          = Color(red: 0.00, green: 0.90, blue: 1.00)   // #00E5FF
    static let accentSoft      = Color(red: 0.00, green: 0.90, blue: 1.00).opacity(0.18)
    /// 警示橙
    static let warn            = Color(red: 1.00, green: 0.54, blue: 0.00)   // #FF8A00
    /// 错误红
    static let danger          = Color(red: 1.00, green: 0.34, blue: 0.40)   // #FF5766

    // 字体
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // 渐变背景
    static var atmosphere: some View {
        ZStack {
            bg.ignoresSafeArea()
            RadialGradient(
                colors: [accent.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 8,
                endRadius: 380
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [warn.opacity(0.10), .clear],
                center: .bottomTrailing,
                startRadius: 8,
                endRadius: 460
            )
            .ignoresSafeArea()
            // 网格线 —— 微光"扫描线"
            GeometryReader { geo in
                let step: CGFloat = 28
                Path { p in
                    var y: CGFloat = 0
                    while y < geo.size.height {
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width, y: y))
                        y += step
                    }
                }
                .stroke(Color.white.opacity(0.025), lineWidth: 0.5)
            }
            .ignoresSafeArea()
        }
    }
}

// MARK: - WelcomeView

/// 首次启动引导页：欢迎语 + 接入按钮
struct WelcomeView: View {

    @Binding var showSubscriptionSheet: Bool
    @State private var pulse: Bool = false
    @State private var revealed: Bool = false

    var body: some View {
        ZStack {
            TVBoxTheme.atmosphere

            VStack(spacing: 0) {
                Spacer(minLength: 24)
                signal
                    .padding(.top, 12)

                Spacer(minLength: 16)

                heading
                    .padding(.horizontal, 28)

                Spacer(minLength: 28)

                metaStrip
                    .padding(.horizontal, 28)

                Spacer(minLength: 24)

                cta
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)

                footer
                    .padding(.bottom, 24)
            }
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 12)
            .animation(.easeOut(duration: 0.55), value: revealed)
        }
        .onAppear {
            revealed = true
            pulse = true
        }
    }

    // MARK: - 子视图

    /// 顶部"信号塔"图形 —— 同心圆 + CRT 光晕
    private var signal: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(TVBoxTheme.accent.opacity(0.35 - Double(i) * 0.10), lineWidth: 1)
                    .frame(width: CGFloat(120 + i * 60), height: CGFloat(120 + i * 60))
                    .scaleEffect(pulse ? 1.06 : 0.96)
                    .animation(
                        .easeInOut(duration: 2.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.25),
                        value: pulse
                    )
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [TVBoxTheme.accent.opacity(0.55), TVBoxTheme.accent.opacity(0.0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .blur(radius: 6)

            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(TVBoxTheme.accent)
                .shadow(color: TVBoxTheme.accent.opacity(0.7), radius: 18)
                .scaleEffect(pulse ? 1.04 : 1.0)
                .animation(
                    .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                    value: pulse
                )
        }
        .frame(height: 260)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(TVBoxTheme.accent)
                    .frame(width: 3, height: 12)
                Text("MYTVBOX // STANDBY")
                    .font(TVBoxTheme.mono(11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(TVBoxTheme.accent)
            }

            Text("欢迎接入。")
                .font(TVBoxTheme.display(40))
                .foregroundStyle(TVBoxTheme.textPrimary)

            Text("添加一个接口地址，即可开始你的影音之旅。\n所有数据仅存储在本机。")
                .font(TVBoxTheme.text(15))
                .foregroundStyle(TVBoxTheme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 三段式步骤指示
    private var metaStrip: some View {
        HStack(spacing: 0) {
            stepItem(num: "01", title: "添加接口", active: true)
            connector
            stepItem(num: "02", title: "解析配置", active: false)
            connector
            stepItem(num: "03", title: "开始观看", active: false)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TVBoxTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(TVBoxTheme.stroke, lineWidth: 1)
        )
    }

    private func stepItem(num: String, title: String, active: Bool) -> some View {
        VStack(spacing: 6) {
            Text(num)
                .font(TVBoxTheme.mono(11, weight: .bold))
                .foregroundStyle(active ? TVBoxTheme.accent : TVBoxTheme.textMuted)
            Text(title)
                .font(TVBoxTheme.text(12, weight: .medium))
                .foregroundStyle(active ? TVBoxTheme.textPrimary : TVBoxTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var connector: some View {
        Rectangle()
            .fill(TVBoxTheme.stroke)
            .frame(width: 1, height: 28)
    }

    private var cta: some View {
        Button {
            showSubscriptionSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.viewfinder")
                    .font(.system(size: 18, weight: .bold))
                Text("添加接口")
                    .font(TVBoxTheme.text(17, weight: .bold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .black))
            }
            .foregroundStyle(Color.black)
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [TVBoxTheme.accent, Color(red: 0.55, green: 1.0, blue: 0.95)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: TVBoxTheme.accent.opacity(0.45), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        Text("v1.0  ·  Connect your own source")
            .font(TVBoxTheme.mono(10))
            .tracking(1.5)
            .foregroundStyle(TVBoxTheme.textMuted)
    }
}

// MARK: - 预览

#Preview {
    WelcomeView(showSubscriptionSheet: .constant(false))
        .preferredColorScheme(.dark)
}
