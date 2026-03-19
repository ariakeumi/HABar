import Charts
import SwiftUI

struct SensorChartCard: View {
    let sensor: SensorDescriptor
    let points: [SensorHistoryPoint]
    let range: HistoryRange
    let color: Color
    @State private var hoveredPoint: SensorHistoryPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(sensor.name)
                    .font(.headline)

                Spacer()

                Text(sensor.formattedValue)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }

            if points.count >= 2 {
                Chart {
                    ForEach(points) { point in
                        AreaMark(
                            x: .value("时间", point.date),
                            y: .value("数值", point.value)
                        )
                        .foregroundStyle(color.opacity(0.15))

                        LineMark(
                            x: .value("时间", point.date),
                            y: .value("数值", point.value)
                        )
                        .foregroundStyle(color)
                        .interpolationMethod(.stepEnd)
                    }

                    if let hoveredPoint {
                        RuleMark(x: .value("悬停时间", hoveredPoint.date))
                            .foregroundStyle(color.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, spacing: 8, overflowResolution: .init(x: .fit, y: .disabled)) {
                                hoverTooltip(for: hoveredPoint)
                            }

                        PointMark(
                            x: .value("悬停时间", hoveredPoint.date),
                            y: .value("悬停数值", hoveredPoint.value)
                        )
                        .foregroundStyle(color)
                        .symbolSize(36)
                    }
                }
                .chartXScale(domain: xDomainStart ... xDomainEnd)
                .chartXAxis {
                    AxisMarks(values: axisDates) { _ in
                        AxisGridLine()
                        AxisTick()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case let .active(location):
                                    guard let plotFrameAnchor = proxy.plotFrame else {
                                        hoveredPoint = nil
                                        return
                                    }

                                    let plotFrame = geometry[plotFrameAnchor]
                                    guard plotFrame.contains(location) else {
                                        hoveredPoint = nil
                                        return
                                    }

                                    let relativeX = location.x - plotFrame.origin.x
                                    guard let date = proxy.value(atX: relativeX, as: Date.self) else {
                                        hoveredPoint = nil
                                        return
                                    }

                                    let nearest = nearestPoint(to: date)
                                    if hoveredPoint?.id != nearest?.id {
                                        hoveredPoint = nearest
                                    }
                                case .ended:
                                    hoveredPoint = nil
                                }
                            }
                    }
                }
                .frame(height: 140)

                HStack(spacing: 0) {
                    ForEach(Array(axisDates.enumerated()), id: \.offset) { index, date in
                        Text(axisLabel(for: date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, alignment: labelAlignment(for: index))
                    }
                }

                HStack {
                    Text("最低 \(SensorValueFormatter.format(minimumValue))\(sensor.unit)")
                    Spacer()
                    Text("最高 \(SensorValueFormatter.format(maximumValue))\(sensor.unit)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("这个传感器还没有足够的历史数据可绘图。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private var minimumValue: Double {
        points.map(\.value).min() ?? sensor.numericValue ?? 0
    }

    private var maximumValue: Double {
        points.map(\.value).max() ?? sensor.numericValue ?? 0
    }

    private var axisCount: Int { 5 }

    private var xDomainStart: Date {
        xDomainEnd.addingTimeInterval(-Double(range.rawValue) * 3600)
    }

    private var xDomainEnd: Date {
        points.last?.date ?? Date()
    }

    private var axisDates: [Date] {
        guard axisCount > 1 else {
            return [xDomainStart]
        }

        let total = xDomainEnd.timeIntervalSince(xDomainStart)
        guard total > 0 else {
            return [xDomainStart]
        }

        let step = total / Double(axisCount - 1)
        return (0..<axisCount).map { index in
            xDomainStart.addingTimeInterval(step * Double(index))
        }
    }

    private func axisLabel(for date: Date) -> String {
        switch range {
        case .last6Hours, .last24Hours:
            return date.formatted(.dateTime.hour().minute())
        case .last7Days:
            return date.formatted(.dateTime.month(.defaultDigits).day().hour())
        }
    }

    private func labelAlignment(for index: Int) -> Alignment {
        if index == 0 {
            return .leading
        }
        if index == axisDates.count - 1 {
            return .trailing
        }
        return .center
    }

    private func nearestPoint(to date: Date) -> SensorHistoryPoint? {
        guard !points.isEmpty else {
            return nil
        }

        var low = 0
        var high = points.count - 1

        while low < high {
            let mid = (low + high) / 2
            if points[mid].date < date {
                low = mid + 1
            } else {
                high = mid
            }
        }

        let current = points[low]
        let previous = low > 0 ? points[low - 1] : nil

        guard let previous else {
            return current
        }

        let currentDistance = abs(current.date.timeIntervalSince(date))
        let previousDistance = abs(previous.date.timeIntervalSince(date))
        return previousDistance <= currentDistance ? previous : current
    }

    @ViewBuilder
    private func hoverTooltip(for point: SensorHistoryPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hoverDateText(for: point))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)

                Text(hoverValueText(for: point))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.18))
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private func hoverValueText(for point: SensorHistoryPoint) -> String {
        let value = SensorValueFormatter.format(point.value)
        return sensor.unit.isEmpty ? value : "\(value)\(sensor.unit)"
    }

    private func hoverDateText(for point: SensorHistoryPoint) -> String {
        point.date.formatted(hoverDateFormatStyle)
    }

    private var hoverDateFormatStyle: Date.FormatStyle {
        switch range {
        case .last6Hours, .last24Hours:
            return .dateTime
                .locale(Locale(identifier: "zh_CN"))
                .year()
                .month(.wide)
                .day()
                .hour()
                .minute()
        case .last7Days:
            return .dateTime
                .locale(Locale(identifier: "zh_CN"))
                .year()
                .month(.wide)
                .day()
                .hour()
        }
    }
}
