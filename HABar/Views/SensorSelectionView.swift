import SwiftUI

/// One shared, searchable list, created only while choosing a sensor.
struct SensorSelectionView: View {
    let sensors: [SensorDescriptor]
    let selectedEntityID: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredSensors: [SensorDescriptor] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sensors }
        return sensors.filter {
            $0.name.localizedStandardContains(query)
                || $0.entityID.localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("选择传感器")
                    .font(.headline)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            TextField("搜索名称或实体 ID", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    selectionRow(name: "不显示", detail: nil, entityID: "")
                    ForEach(filteredSensors) { sensor in
                        selectionRow(
                            name: sensor.unit.isEmpty ? sensor.name : "\(sensor.name) (\(sensor.unit))",
                            detail: sensor.entityID,
                            entityID: sensor.entityID
                        )
                    }
                    if filteredSensors.isEmpty {
                        Text("没有匹配的传感器")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 460, height: 420)
    }

    private func selectionRow(name: String, detail: String?, entityID: String) -> some View {
        Button {
            onSelect(entityID)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .foregroundStyle(.primary)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer()
                if selectedEntityID == entityID {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedEntityID == entityID ? .isSelected : [])
    }
}
