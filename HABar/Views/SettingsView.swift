import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: HomeAssistantStore

    var body: some View {
        Form {
            Section("Home Assistant") {
                LabeledContent("地址") {
                    TextField("", text: $store.draftBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                }

                LabeledContent("令牌") {
                    SecureField("", text: $store.draftToken)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                }

                HStack {
                    Button("保存并连接") {
                        Task {
                            await store.saveConnectionSettings()
                        }
                    }
                    .keyboardShortcut(.defaultAction)

                    Button("立即刷新") {
                        Task {
                            await store.refresh()
                        }
                    }
                    .disabled(!store.isConfigured)
                }
            }

            Section("应用") {
                Toggle("开机自启动", isOn: Binding(
                    get: { store.launchAtLoginSelection },
                    set: { store.setLaunchAtLogin($0) }
                ))

                if store.launchAtLoginRequiresApproval {
                    HStack {
                        Text("系统需要你在登录项里批准该应用。")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("打开登录项设置") {
                            store.openLoginItemsSettings()
                        }
                    }
                }
            }

            Section("菜单栏显示（1-3 个）") {
                sensorSelectionContent(count: HAConfiguration.menuBarSlotCount, selection: store.menuBarSelection(at:), setter: store.setMenuBarSensor(_:at:), titlePrefix: "菜单栏")
            }

            Section("卡片界面图表（1-4 个）") {
                chartSelectionContent()
            }

            Section("历史图表") {
                Picker("时间范围", selection: Binding(
                    get: { store.configuration.historyRange },
                    set: { store.setHistoryRange($0) }
                )) {
                    ForEach(HistoryRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
            }

            Section {
                Text(store.sensorCountText)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = store.errorMessage {
                Section("状态") {
                    Text(errorMessage)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let launchAtLoginError = store.launchAtLoginError {
                Section("开机自启动状态") {
                    Text(launchAtLoginError)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 620)
        .padding(20)
    }

    @ViewBuilder
    private func sensorSelectionContent(
        count: Int,
        selection: @escaping (Int) -> String,
        setter: @escaping (String, Int) -> Void,
        titlePrefix: String
    ) -> some View {
        if store.availableSensors.isEmpty {
            Text("保存连接信息后，这里会列出 Home Assistant 中可选的 `sensor.*` 实体。")
                .foregroundStyle(.secondary)
        } else {
            ForEach(0..<count, id: \.self) { index in
                Picker("\(titlePrefix) \(index + 1)", selection: Binding(
                    get: { selection(index) },
                    set: { setter($0, index) }
                )) {
                    Text("不显示").tag("")
                    ForEach(store.sensorCandidates()) { sensor in
                        Text(sensorOptionLabel(sensor)).tag(sensor.entityID)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chartSelectionContent() -> some View {
        if store.availableSensors.isEmpty {
            Text("保存连接信息后，这里会列出 Home Assistant 中可选的 `sensor.*` 实体。")
                .foregroundStyle(.secondary)
        } else {
            ForEach(0..<HAConfiguration.chartSlotCount, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    Picker("图表 \(index + 1)", selection: Binding(
                        get: { store.chartSelection(at: index) },
                        set: { store.setChartSensor($0, at: index) }
                    )) {
                        Text("不显示").tag("")
                        ForEach(store.sensorCandidates()) { sensor in
                            Text(sensorOptionLabel(sensor)).tag(sensor.entityID)
                        }
                    }

                    Picker("颜色", selection: Binding(
                        get: { store.chartColor(at: index) },
                        set: { store.setChartColor($0, at: index) }
                    )) {
                        ForEach(ChartColorOption.allCases) { color in
                            Text(color.title).tag(color)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func sensorOptionLabel(_ sensor: SensorDescriptor) -> String {
        if sensor.unit.isEmpty {
            return sensor.name
        }

        return "\(sensor.name) (\(sensor.unit))"
    }
}
