import Charts
import SwiftUI

struct SensorChartCard: View {
    let sensor: SensorDescriptor
    let points: [SensorHistoryPoint]
    let range: HistoryRange
    let color: Color

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
                Chart(points) { point in
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
}
