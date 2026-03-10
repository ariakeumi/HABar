import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: HomeAssistantStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if store.isConfigured {
                if store.chartSelectionCount == 0 {
                    emptySelection
                } else {
                    rangePicker

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(store.chartSelections) { selection in
                            HStack {
                                Spacer(minLength: 0)
                                SensorChartCard(
                                    sensor: selection.sensor,
                                    points: store.historyPoints(for: selection.entityID),
                                    range: store.configuration.historyRange,
                                    color: store.chartColor(at: selection.slotIndex).swiftUIColor
                                )
                                .frame(width: 350)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            } else {
                onboarding
            }

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(width: 382)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Home Assistant")
                    .font(.headline)

                if let lastRefresh = store.lastRefresh {
                    Text("最近刷新 \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("等待首次同步")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                } else {
                    iconButton(systemName: "arrow.clockwise") {
                        Task {
                            await store.refresh()
                        }
                    }
                }

                iconButton(systemName: "gearshape") {
                    openSettings()
                }

                iconButton(systemName: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private var rangePicker: some View {
        Picker("历史范围", selection: Binding(
            get: { store.configuration.historyRange },
            set: { store.setHistoryRange($0) }
        )) {
            ForEach(HistoryRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    private var onboarding: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("先连接到 Home Assistant")
                .font(.headline)
            Text("在设置中填写实例地址和长期访问令牌，然后分别配置菜单栏要显示的传感器，以及卡片界面要展示的图表。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptySelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("尚未选择图表传感器")
                .font(.headline)
            Text("打开设置后，在卡片界面图表区域选择 1 到 4 个传感器。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}
