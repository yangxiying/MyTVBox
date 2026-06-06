import SwiftUI

/// 定时关闭选择弹窗
/// 选项：15 / 30 / 45 / 60 / 90 分钟、播完当前
/// 已设置时显示剩余时间与取消按钮
struct SleepTimerView: View {

    @ObservedObject private var manager = AudioPlayerManager.shared
    @Environment(\.dismiss) private var dismiss

    private let options: [Int] = [15, 30, 45, 60, 90]

    var body: some View {
        VStack(spacing: 0) {
            handle
                .padding(.top, 8)

            header
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 16)

            if manager.hasSleepTimer {
                activeStatusCard
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(options, id: \.self) { mins in
                        timerOptionRow(minutes: mins)
                    }
                    timerOptionRowCustom(
                        title: "播完当前曲目",
                        icon: "music.note.list",
                        isSelected: manager.sleepUntilTrackEnds
                    ) {
                        manager.setSleepUntilTrackEnds()
                        dismiss()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
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
                Text("定时关闭")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                Text("到时间后自动暂停播放")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.10)))
        }
    }

    private var activeStatusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "timer")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Color(red: 0.10, green: 0.08, blue: 0.18))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white))

            VStack(alignment: .leading, spacing: 2) {
                Text(manager.sleepUntilTrackEnds ? "播完当前曲目后停止" : "剩余时间")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                Text(activeText)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundColor(.white)
            }
            Spacer()
            Button {
                manager.cancelSleepTimer()
            } label: {
                Text("取消")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color.white.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }

    private var activeText: String {
        if manager.sleepUntilTrackEnds {
            return "—"
        }
        if let r = manager.sleepTimerRemaining {
            return AudioPlayerManager.formatTime(r)
        }
        return "—"
    }

    private func timerOptionRow(minutes: Int) -> some View {
        let isSelected = !manager.sleepUntilTrackEnds
            && manager.sleepTimerRemaining != nil
            && abs((manager.sleepTimerRemaining ?? 0) - Double(minutes * 60)) < 60

        return Button {
            manager.setSleepTimer(minutes: minutes)
            dismiss()
        } label: {
            optionContent(
                title: "\(minutes) 分钟",
                icon: "clock",
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
    }

    private func timerOptionRowCustom(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            optionContent(title: title, icon: icon, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func optionContent(title: String, icon: String, isSelected: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isSelected ? Color(red: 0.10, green: 0.08, blue: 0.18) : .white.opacity(0.85))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isSelected ? Color.white : Color.white.opacity(0.10))
                )
            Text(title)
                .font(.body.weight(.medium))
                .foregroundColor(.white)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.12 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(isSelected ? 0.20 : 0.06), lineWidth: 0.5)
                )
        )
    }
}

#if DEBUG
#if compiler(>=5.9)
@available(iOS 17, *)
struct Preview_SleepTimerView: PreviewProvider {
    static var previews: some View {
        SleepTimerView()
    }
}
#endif

#endif
