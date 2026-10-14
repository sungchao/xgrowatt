import SwiftUI
import Charts

struct CumulativeTelemetryEntry: Identifiable {
    let id: String
    let timestamp: Date
    let cumulativeSolar: Double
    let cumulativeLoad: Double
    let cumulativeCharge: Double
    let cumulativeDischarge: Double
    let cumulativeImport: Double
    let cumulativeExport: Double
}

struct TelemetryChartView: View {
    @ObservedObject var fm = FirebaseManager.shared
    @ObservedObject var live = FirebaseManager.shared.live
    @Binding var isScrubbing: Bool
    
    // Theme Colors
    private let solarGold = Theme.solarGold
    private let batteryGreen = Theme.batteryGreen
    private let loadBlue = Theme.loadBlue
    private let gridPurple = Theme.gridPurple
    private let alertRed = Theme.alertRed
    // Per-MPPT string colors (used for both power lines and voltage lines)
    private let pv1Cyan = Theme.pv1Cyan
    private let pv2Pink = Theme.pv2Pink
    
    // Interaction States
    @State private var selectedDate: Date? = nil
    @State private var zoomHours: Double = 24.0 // Zoom level in hours (1.0 to 24.0)
    @State private var panPosition: Double = 0.5 // 0.0 (start of day) to 1.0 (end of day)

    // Series visibility — shared by both charts so one tap hides a series everywhere.
    // Keys: solar, load, charge, discharge, import, export, soc
    @State private var hiddenSeries: Set<String> = []

    private func isVisible(_ key: String) -> Bool { !hiddenSeries.contains(key) }

    private func toggleSeries(_ key: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if hiddenSeries.contains(key) {
                hiddenSeries.remove(key)
            } else {
                hiddenSeries.insert(key)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Card title inside the card, matching the app-wide pattern
            HStack {
                Label("24-HOUR ENERGY PROFILES", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(batteryGreen)
                    .tracking(1.5)
                Spacer()
            }
            .padding(.horizontal, 4)

            if filteredTelemetry.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No telemetry data captured today")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Force sync or refresh live data to begin logging for today.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 300)
                .frame(maxWidth: .infinity)
            } else {
                // 1. Controls Header: Zoom Presets — hidden while scrubbing so the tooltip
                // that appears above (Section 2) has the space and attention to itself.
                if selectedDate == nil {
                    HStack(spacing: 8) {
                        Text("Time Frame:")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        Spacer()

                        ForEach([24, 12, 6, 2, 1], id: \.self) { hours in
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    zoomHours = Double(hours)
                                    // Default a newly-picked window to the most recent data
                                    // (i.e. ending at "now") rather than leaving it centered
                                    // on wherever the slider happened to be before.
                                    panPosition = 1.0
                                    clampPanPosition()
                                }
                            }) {
                                Text("\(hours)H")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(zoomHours == Double(hours) ? batteryGreen : Color.white.opacity(0.04))
                                    .foregroundColor(zoomHours == Double(hours) ? .black : .white)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // 2. Interactive Tooltip Panel (Only visible when scrubbing)
                if let selectedDate = selectedDate, let entry = closestEntry(to: selectedDate) {
                    let cumulative = cumulativeValues(upTo: entry.timestamp ?? Date())
                    TooltipView(
                        entry: entry,
                        solarKwh: cumulative.solar,
                        loadKwh: cumulative.load,
                        chargeKwh: cumulative.charge,
                        dischargeKwh: cumulative.discharge,
                        importKwh: cumulative.gridImport,
                        exportKwh: cumulative.gridExport,
                        hidden: hiddenSeries
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    // Placeholder tip to invite scrubbing
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(batteryGreen.opacity(0.8))
                        Text("Hold and drag across charts to scrub exact values")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(height: 38)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(8)
                }
                
                // Compute visible range based on zoom level and pan position
                let timeRange = visibleRange()
                
                // 3. Chart 1: Power Flow & SoC Chart
                PowerFlowChart(timeRange: timeRange)
                
                Divider()
                    .background(Color.white.opacity(0.08))
                
                // 4. Chart 2: Cumulative Energy Chart
                CumulativeEnergyChart(timeRange: timeRange)
                
                // 6. Sleek Pan Slider (Only shown when zoomed in)
                if zoomHours < 24.0 {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 10))
                                .foregroundColor(batteryGreen)
                            Text("DRAG TO SCROLL TIMELINE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                                .tracking(1)
                            Spacer()
                            Text(timeRangeString(for: timeRange))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(batteryGreen)
                        }
                        
                        Slider(value: $panPosition, in: zoomRatioRange().0...zoomRatioRange().1)
                            .tint(batteryGreen)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.04), lineWidth: 1)
                    )
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .padding()
        .glassCardStyle(cornerRadius: 18)
        .animation(.easeInOut(duration: 0.2), value: selectedDate == nil)
        .onAppear { rebuildCaches() }
        .onChange(of: live.telemetryHistory.count) { rebuildCaches() }
        .onChange(of: live.telemetryHistory.last?.id) { rebuildCaches() }
    }
    
    // MARK: - Core Helper Calculations

    // PERFORMANCE: filter/sort/integration results are cached in @State and rebuilt only
    // when new telemetry arrives — computed properties here used to re-run (filter + sort
    // over 300 entries, then a full trapezoid integration) on every body evaluation, and
    // body evaluates once per frame while scrubbing. That was the main source of jank.
    @State private var cachedTelemetry: [TelemetryEntry] = []
    @State private var cachedCumulative: [CumulativeTelemetryEntry] = []

    private var filteredTelemetry: [TelemetryEntry] { cachedTelemetry }
    private var cumulativeTelemetry: [CumulativeTelemetryEntry] { cachedCumulative }

    private func rebuildCaches() {
        cachedTelemetry = computeFilteredTelemetry()
        cachedCumulative = computeCumulative(from: cachedTelemetry)
    }

    /// Thins a series to ~`target` points for DISPLAY only (scrub tooltips still read the
    /// full-resolution cache). ~150 points per line is visually indistinguishable at chart
    /// width but cuts Swift Charts' mark count — the other source of first-render lag.
    private func downsample<T>(_ points: [T], target: Int = 150) -> [T] {
        guard points.count > target, target > 1 else { return points }
        let step = Double(points.count - 1) / Double(target - 1)
        var indices = Set<Int>()
        for k in 0..<target {
            indices.insert(Int((Double(k) * step).rounded()))
        }
        return indices.sorted().map { points[$0] }
    }

    private func computeFilteredTelemetry() -> [TelemetryEntry] {
        let cal = Calendar.current
        var userTz = TimeZone.current
        if let tz = TimeZone(identifier: fm.settings.timezone) {
            userTz = tz
        }
        var tzCal = cal
        tzCal.timeZone = userTz
        let startOfToday = tzCal.startOfDay(for: Date())

        return live.telemetryHistory
            .filter { ($0.timestamp ?? Date.distantPast) >= startOfToday }
            .sorted { ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) }
    }

    private func computeCumulative(from sorted: [TelemetryEntry]) -> [CumulativeTelemetryEntry] {
        guard sorted.count > 1 else { return [] }
        
        var result: [CumulativeTelemetryEntry] = []
        var runningSolar = 0.0
        var runningLoad = 0.0
        var runningCharge = 0.0
        var runningDischarge = 0.0
        var runningImport = 0.0
        var runningExport = 0.0
        
        if let first = sorted.first, let t0 = first.timestamp {
            result.append(CumulativeTelemetryEntry(
                id: first.id ?? UUID().uuidString,
                timestamp: t0,
                cumulativeSolar: 0.0,
                cumulativeLoad: 0.0,
                cumulativeCharge: 0.0,
                cumulativeDischarge: 0.0,
                cumulativeImport: 0.0,
                cumulativeExport: 0.0
            ))
        }
        
        for i in 0..<(sorted.count - 1) {
            let e1 = sorted[i]
            let e2 = sorted[i+1]
            guard let t1 = e1.timestamp, let t2 = e2.timestamp else { continue }
            let dtHours = t2.timeIntervalSince(t1) / 3600.0
            
            if dtHours < 1.0 {
                runningSolar += ((e1.solar_generation_kw + e2.solar_generation_kw) / 2.0) * dtHours
                runningLoad += ((e1.local_load_kw + e2.local_load_kw) / 2.0) * dtHours
                runningCharge += ((e1.charge_power_kw + e2.charge_power_kw) / 2.0) * dtHours
                runningDischarge += ((e1.discharge_power_kw + e2.discharge_power_kw) / 2.0) * dtHours
                runningImport += ((e1.grid_import_kw + e2.grid_import_kw) / 2.0) * dtHours
                runningExport += ((e1.grid_export_kw + e2.grid_export_kw) / 2.0) * dtHours
            }
            
            result.append(CumulativeTelemetryEntry(
                id: e2.id ?? UUID().uuidString,
                timestamp: t2,
                cumulativeSolar: runningSolar,
                cumulativeLoad: runningLoad,
                cumulativeCharge: runningCharge,
                cumulativeDischarge: runningDischarge,
                cumulativeImport: runningImport,
                cumulativeExport: runningExport
            ))
        }
        return result
    }
    
    private func cumulativeValues(upTo targetDate: Date) -> (solar: Double, load: Double, charge: Double, discharge: Double, gridImport: Double, gridExport: Double) {
        let sorted = filteredTelemetry
        var runningSolar = 0.0
        var runningLoad = 0.0
        var runningCharge = 0.0
        var runningDischarge = 0.0
        var runningImport = 0.0
        var runningExport = 0.0
        
        guard sorted.count > 1 else { return (0, 0, 0, 0, 0, 0) }
        
        for i in 0..<(sorted.count - 1) {
            let e1 = sorted[i]
            let e2 = sorted[i+1]
            guard let t1 = e1.timestamp, let t2 = e2.timestamp else { continue }
            if t2 > targetDate { break }
            let dtHours = t2.timeIntervalSince(t1) / 3600.0
            
            if dtHours < 1.0 {
                runningSolar += ((e1.solar_generation_kw + e2.solar_generation_kw) / 2.0) * dtHours
                runningLoad += ((e1.local_load_kw + e2.local_load_kw) / 2.0) * dtHours
                runningCharge += ((e1.charge_power_kw + e2.charge_power_kw) / 2.0) * dtHours
                runningDischarge += ((e1.discharge_power_kw + e2.discharge_power_kw) / 2.0) * dtHours
                runningImport += ((e1.grid_import_kw + e2.grid_import_kw) / 2.0) * dtHours
                runningExport += ((e1.grid_export_kw + e2.grid_export_kw) / 2.0) * dtHours
            }
        }
        return (runningSolar, runningLoad, runningCharge, runningDischarge, runningImport, runningExport)
    }

    private func visibleRange() -> ClosedRange<Date> {
        let history = filteredTelemetry
        
        var userTz = TimeZone.current
        if let tz = TimeZone(identifier: fm.settings.timezone) {
            userTz = tz
        }
        var cal = Calendar.current
        cal.timeZone = userTz
        let startOfToday = cal.startOfDay(for: Date())
        let now = Date()
        
        guard !history.isEmpty else {
            return startOfToday...now
        }
        
        let first = startOfToday
        let last = max(now, history.last?.timestamp ?? now)
        
        let totalSpan = last.timeIntervalSince(first)
        let visibleSpan = zoomHours * 3600.0
        
        if visibleSpan >= totalSpan {
            return first...last
        }
        
        // Calculate offset based on panPosition slider (0.0 to 1.0)
        let centerOffset = totalSpan * panPosition
        let centerDate = first.addingTimeInterval(centerOffset)
        
        var minDate = centerDate.addingTimeInterval(-visibleSpan / 2.0)
        var maxDate = centerDate.addingTimeInterval(visibleSpan / 2.0)
        
        // Safety Clamping
        if minDate < first {
            let diff = first.timeIntervalSince(minDate)
            minDate = first
            maxDate = maxDate.addingTimeInterval(diff)
        }
        if maxDate > last {
            let diff = maxDate.timeIntervalSince(last)
            maxDate = last
            minDate = max(first, minDate.addingTimeInterval(-diff))
        }
        
        return minDate...maxDate
    }
    
    private func zoomRatioRange() -> (Double, Double) {
        let history = filteredTelemetry
        
        var userTz = TimeZone.current
        if let tz = TimeZone(identifier: fm.settings.timezone) {
            userTz = tz
        }
        var cal = Calendar.current
        cal.timeZone = userTz
        let first = cal.startOfDay(for: Date())
        let last = max(Date(), history.last?.timestamp ?? Date())
        
        let totalSpan = last.timeIntervalSince(first)
        let visibleSpan = zoomHours * 3600.0
        if visibleSpan >= totalSpan {
            return (0.5, 0.5)
        }
        let halfRatio = (visibleSpan / 2.0) / totalSpan
        return (halfRatio, 1.0 - halfRatio)
    }
    
    private func clampPanPosition() {
        let bounds = zoomRatioRange()
        if panPosition < bounds.0 { panPosition = bounds.0 }
        if panPosition > bounds.1 { panPosition = bounds.1 }
    }
    
    private func closestEntry(to date: Date) -> TelemetryEntry? {
        let history = filteredTelemetry
        guard !history.isEmpty else { return nil }
        return history.min(by: {
            abs($0.timestamp?.timeIntervalSince(date) ?? 0) < abs($1.timestamp?.timeIntervalSince(date) ?? 0)
        })
    }
    
    private func timeRangeString(for range: ClosedRange<Date>) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return "\(df.string(from: range.lowerBound)) - \(df.string(from: range.upperBound))"
    }
    
    // MARK: - Sub-components: Charts
    
    @ViewBuilder
    private func PowerFlowChart(timeRange: ClosedRange<Date>) -> some View {
        let visibleTelemetry = downsample(filteredTelemetry.filter { entry in
            guard let date = entry.timestamp else { return false }
            return timeRange.contains(date)
        })
        // Y-scale considers only VISIBLE series, so hiding a big series (e.g. Charge at 5 kW)
        // rescales the chart to give the remaining curves more resolution.
        let maxPower = max(2.0, visibleTelemetry.flatMap { entry -> [Double] in
            var values: [Double] = []
            if isVisible("solar") { values.append(entry.solar_generation_kw) }
            if isVisible("load") { values.append(entry.local_load_kw) }
            if isVisible("charge") { values.append(entry.charge_power_kw) }
            if isVisible("discharge") { values.append(entry.discharge_power_kw) }
            if isVisible("import") { values.append(entry.grid_import_kw) }
            if isVisible("export") { values.append(entry.grid_export_kw) }
            if isVisible("pv1"), let p = entry.pv1_power_kw { values.append(p) }
            if isVisible("pv2"), let p = entry.pv2_power_kw { values.append(p) }
            return values
        }.max() ?? 5.0)
        
        VStack(alignment: .leading, spacing: 6) {
            Text("Power Flow (kW) & Battery SoC (%)")
                .font(.footnote)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            // Legend — wraps to multiple rows (no scrolling); tap an item to hide/show its series
            FlowLayout(spacing: 10) {
                LegendItem(color: solarGold, label: "Solar", isActive: isVisible("solar")) { toggleSeries("solar") }
                LegendItem(color: pv1Cyan, label: "PV1", isActive: isVisible("pv1")) { toggleSeries("pv1") }
                LegendItem(color: pv2Pink, label: "PV2", isActive: isVisible("pv2")) { toggleSeries("pv2") }
                LegendItem(color: loadBlue, label: "Load", isActive: isVisible("load")) { toggleSeries("load") }
                LegendItem(color: batteryGreen, label: "Charge", isActive: isVisible("charge")) { toggleSeries("charge") }
                LegendItem(color: .orange, label: "Discharge", isActive: isVisible("discharge")) { toggleSeries("discharge") }
                LegendItem(color: gridPurple, label: "Grid Import", isActive: isVisible("import")) { toggleSeries("import") }
                LegendItem(color: alertRed, label: "Grid Export", isActive: isVisible("export")) { toggleSeries("export") }
                LegendItem(color: batteryGreen, label: "BMS SoC", dashed: true, isActive: isVisible("soc")) { toggleSeries("soc") }
                LegendItem(color: .cyan, label: "AI SoC", dashed: true, isActive: isVisible("ai_soc")) { toggleSeries("ai_soc") }
            }
            .padding(.bottom, 4)
            
            Chart {
                ForEach(visibleTelemetry) { entry in
                    if let date = entry.timestamp {
                        // AI Physics Modeled SoC Trend Line (Cyan Dashed)
                        let modeledSocVal = entry.modeled_soc ?? Double(entry.soc)
                        let scaledAISoC = (modeledSocVal / 100.0) * maxPower
                        if isVisible("ai_soc") {
                            LineMark(
                                x: .value("Time", date),
                                y: .value("AI SoC", scaledAISoC),
                                series: .value("Series", "AI SoC")
                            )
                            .foregroundStyle(Color.cyan.opacity(0.85))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                        }

                        // Battery SoC Background Area (scaled to maxPower)
                        let scaledSoC = (Double(entry.soc) / 100.0) * maxPower
                        if isVisible("soc") {
                            AreaMark(
                                x: .value("Time", date),
                                yStart: .value("Base", 0.0),
                                yEnd: .value("Battery SoC", scaledSoC)
                            )
                            .foregroundStyle(LinearGradient(
                                colors: [batteryGreen.opacity(0.06), batteryGreen.opacity(0.00)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))

                            // Battery SoC Trend Line (Dashed)
                            LineMark(
                                x: .value("Time", date),
                                y: .value("Battery SoC", scaledSoC),
                                series: .value("Series", "Battery SoC")
                            )
                            .foregroundStyle(batteryGreen.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                        }

                        if isVisible("solar") {
                            LineMark(
                                x: .value("Time", date),
                                y: .value("Power", entry.solar_generation_kw),
                                series: .value("Series", "Solar")
                            )
                            .foregroundStyle(solarGold)
                            .lineStyle(StrokeStyle(lineWidth: 1.8))
                        }

                        if isVisible("pv1"), let pv1 = entry.pv1_power_kw {
                            LineMark(
                                x: .value("Time", date),
                                y: .value("Power", pv1),
                                series: .value("Series", "PV1")
                            )
                            .foregroundStyle(pv1Cyan)
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
                        }

                        if isVisible("pv2"), let pv2 = entry.pv2_power_kw {
                            LineMark(
                                x: .value("Time", date),
                                y: .value("Power", pv2),
                                series: .value("Series", "PV2")
                            )
                            .foregroundStyle(pv2Pink)
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
                        }

                        if isVisible("load") {
                            LineMark(
                                x: .value("Time", date),
                                y: .value("Power", entry.local_load_kw),
                                series: .value("Series", "Load")
                            )
                            .foregroundStyle(loadBlue)
                            .lineStyle(StrokeStyle(lineWidth: 1.8))
                        }

                        if isVisible("charge") {
                            LineMark(
                                x: .value("Time", date),
                                y: .value("Power", entry.charge_power_kw),
                                series: .value("Series", "Charge")
                            )
                            .foregroundStyle(batteryGreen)
                            .lineStyle(StrokeStyle(lineWidth: 1.8))
                        }

                        if isVisible("discharge") {
                            LineMark(
                                x: .value("Time", date),
                                y: .value("Power", entry.discharge_power_kw),
                                series: .value("Series", "Discharge")
                            )
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1.8))
                        }

                        if isVisible("import") {
                            LineMark(
                                x: .value("Time", date),
                                y: .value("Power", entry.grid_import_kw),
                                series: .value("Series", "Grid Import")
                            )
                            .foregroundStyle(gridPurple)
                            .lineStyle(StrokeStyle(lineWidth: 1.8))
                        }

                        if isVisible("export") {
                            LineMark(
                                x: .value("Time", date),
                                y: .value("Power", entry.grid_export_kw),
                                series: .value("Series", "Grid Export")
                            )
                            .foregroundStyle(alertRed)
                            .lineStyle(StrokeStyle(lineWidth: 1.8))
                        }
                    }
                }
                
                // Draw vertical indicator line when scrubbing
                if let selectedDate = selectedDate, let entry = closestEntry(to: selectedDate), let entryDate = entry.timestamp {
                    RuleMark(x: .value("Selected Time", entryDate))
                        .foregroundStyle(batteryGreen.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                }
            }
            .frame(height: 160)
            .chartXScale(domain: timeRange)
            .chartYScale(domain: 0...maxPower)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.white.opacity(0.15))
                    if let power = value.as(Double.self) {
                        AxisValueLabel {
                            Text(String(format: "%.1f", power))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.8))
                        }
                    }
                }
                AxisMarks(position: .trailing, values: [0, 20, 40, 60, 80, 100].map { ($0 / 100.0) * maxPower }) { value in
                    if let scaledVal = value.as(Double.self) {
                        let percentage = (scaledVal / maxPower) * 100.0
                        AxisValueLabel {
                            Text("\(Int(round(percentage)))%")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(batteryGreen.opacity(0.9))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.white.opacity(0.15))
                    AxisValueLabel(format: .dateTime.hour().minute(), anchor: .top)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.8))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 10)
                                .onChanged { drag in
                                    if let plotFrame = proxy.plotFrame {
                                        isScrubbing = true
                                        let origin = geo[plotFrame].origin
                                        let location = CGPoint(
                                            x: drag.location.x - origin.x,
                                            y: drag.location.y - origin.y
                                        )
                                        if let date: Date = proxy.value(atX: location.x) {
                                            selectedDate = date
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    isScrubbing = false
                                    selectedDate = nil
                                }
                        )
                }
            }
        }
    }
    
    @ViewBuilder
    private func CumulativeEnergyChart(timeRange: ClosedRange<Date>) -> some View {
        let visibleCumulative = downsample(cumulativeTelemetry.filter { entry in
            timeRange.contains(entry.timestamp)
        })
        // Instantaneous per-string voltages ride on the right axis (scaled into the kWh
        // domain like SoC on the power chart) — reuses the previously blank trailing axis.
        let visiblePoints = downsample(filteredTelemetry.filter { entry in
            guard let date = entry.timestamp else { return false }
            return timeRange.contains(date)
        })
        let maxEnergy = max(1.0, visibleCumulative.flatMap { entry -> [Double] in
            var values: [Double] = []
            if isVisible("solar") { values.append(entry.cumulativeSolar) }
            if isVisible("load") { values.append(entry.cumulativeLoad) }
            if isVisible("charge") { values.append(entry.cumulativeCharge) }
            if isVisible("discharge") { values.append(entry.cumulativeDischarge) }
            if isVisible("import") { values.append(entry.cumulativeImport) }
            if isVisible("export") { values.append(entry.cumulativeExport) }
            return values
        }.max() ?? 5.0)
        let voltages = visiblePoints.flatMap { [$0.pv1_voltage, $0.pv2_voltage].compactMap { $0 } }
        let showVoltage = !voltages.isEmpty && (isVisible("v1") || isVisible("v2"))
        let maxVoltage = max(100.0, (voltages.max() ?? 400.0) * 1.1)

        VStack(alignment: .leading, spacing: 6) {
            Text("Cumulative Energy Today (kWh)" + (showVoltage ? " · String Voltage (V)" : ""))
                .font(.footnote)
                .fontWeight(.bold)
                .foregroundColor(.white)

            // Legend — same shared visibility keys as the power chart
            FlowLayout(spacing: 10) {
                LegendItem(color: solarGold, label: "Solar Yield", isActive: isVisible("solar")) { toggleSeries("solar") }
                LegendItem(color: loadBlue, label: "Load Cons", isActive: isVisible("load")) { toggleSeries("load") }
                LegendItem(color: batteryGreen, label: "Battery Chg", isActive: isVisible("charge")) { toggleSeries("charge") }
                LegendItem(color: .orange, label: "Battery Disch", isActive: isVisible("discharge")) { toggleSeries("discharge") }
                LegendItem(color: gridPurple, label: "Grid Import", isActive: isVisible("import")) { toggleSeries("import") }
                LegendItem(color: alertRed, label: "Grid Export", isActive: isVisible("export")) { toggleSeries("export") }
                LegendItem(color: pv1Cyan, label: "PV1 Volt", dashed: true, isActive: isVisible("v1")) { toggleSeries("v1") }
                LegendItem(color: pv2Pink, label: "PV2 Volt", dashed: true, isActive: isVisible("v2")) { toggleSeries("v2") }
            }
            .padding(.bottom, 4)
            
            Chart {
                ForEach(visibleCumulative) { entry in
                    if isVisible("solar") {
                        LineMark(
                            x: .value("Time", entry.timestamp),
                            y: .value("Energy", entry.cumulativeSolar),
                            series: .value("Series", "Solar Yield")
                        )
                        .foregroundStyle(solarGold)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                    }

                    if isVisible("load") {
                        LineMark(
                            x: .value("Time", entry.timestamp),
                            y: .value("Energy", entry.cumulativeLoad),
                            series: .value("Series", "Load Cons")
                        )
                        .foregroundStyle(loadBlue)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                    }

                    if isVisible("charge") {
                        LineMark(
                            x: .value("Time", entry.timestamp),
                            y: .value("Energy", entry.cumulativeCharge),
                            series: .value("Series", "Battery Chg")
                        )
                        .foregroundStyle(batteryGreen)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                    }

                    if isVisible("discharge") {
                        LineMark(
                            x: .value("Time", entry.timestamp),
                            y: .value("Energy", entry.cumulativeDischarge),
                            series: .value("Series", "Battery Disch")
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                    }

                    if isVisible("import") {
                        LineMark(
                            x: .value("Time", entry.timestamp),
                            y: .value("Energy", entry.cumulativeImport),
                            series: .value("Series", "Grid Import")
                        )
                        .foregroundStyle(gridPurple)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                    }

                    if isVisible("export") {
                        LineMark(
                            x: .value("Time", entry.timestamp),
                            y: .value("Energy", entry.cumulativeExport),
                            series: .value("Series", "Grid Export")
                        )
                        .foregroundStyle(alertRed)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                    }
                }
                
                // Per-string voltage overlay (instantaneous, right-axis scale)
                ForEach(visiblePoints) { entry in
                    if let date = entry.timestamp {
                        if isVisible("v1"), let v1 = entry.pv1_voltage {
                            LineMark(
                                x: .value("Time", date),
                                y: .value("Voltage", (v1 / maxVoltage) * maxEnergy),
                                series: .value("Series", "PV1 Volt")
                            )
                            .foregroundStyle(pv1Cyan.opacity(0.85))
                            .lineStyle(StrokeStyle(lineWidth: 1.1, dash: [3, 3]))
                        }
                        if isVisible("v2"), let v2 = entry.pv2_voltage {
                            LineMark(
                                x: .value("Time", date),
                                y: .value("Voltage", (v2 / maxVoltage) * maxEnergy),
                                series: .value("Series", "PV2 Volt")
                            )
                            .foregroundStyle(pv2Pink.opacity(0.85))
                            .lineStyle(StrokeStyle(lineWidth: 1.1, dash: [3, 3]))
                        }
                    }
                }

                if let selectedDate = selectedDate, let entry = closestEntry(to: selectedDate), let entryDate = entry.timestamp {
                    RuleMark(x: .value("Selected Time", entryDate))
                        .foregroundStyle(batteryGreen.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                }
            }
            .frame(height: 150)
            .chartXScale(domain: timeRange)
            .chartYScale(domain: 0...(maxEnergy * 1.05))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.white.opacity(0.15))
                    if let power = value.as(Double.self) {
                        AxisValueLabel {
                            Text(String(format: "%.1f", power))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.8))
                        }
                    }
                }
                // Trailing axis: string voltage scale when shown, else a blank spacer that
                // keeps this chart's plot width aligned with the power chart above.
                AxisMarks(position: .trailing, values: [0, 0.25, 0.5, 0.75, 1.0].map { $0 * maxEnergy }) { value in
                    if let scaled = value.as(Double.self) {
                        AxisValueLabel {
                            if showVoltage {
                                Text("\(Int(round((scaled / maxEnergy) * maxVoltage)))V")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(pv1Cyan.opacity(0.9))
                            } else {
                                Text(" ")
                                    .frame(width: 36, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.white.opacity(0.15))
                    AxisValueLabel(format: .dateTime.hour().minute(), anchor: .top)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.8))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 10)
                                .onChanged { drag in
                                    if let plotFrame = proxy.plotFrame {
                                        isScrubbing = true
                                        let origin = geo[plotFrame].origin
                                        let location = CGPoint(
                                            x: drag.location.x - origin.x,
                                            y: drag.location.y - origin.y
                                        )
                                        if let date: Date = proxy.value(atX: location.x) {
                                            selectedDate = date
                                        }
                                    }
                                }
                                .onEnded { _ in
                                    isScrubbing = false
                                    selectedDate = nil
                                }
                        )
                }
            }
        }
    }
}

// MARK: - 24h Weather Forecast Card (Solar Analytics page)
// Solar-first presentation: hourly GTI bars ("solar fuel" — the shape of tomorrow's
// generation), a 3-hourly icon+temperature strip for weather intuition, and a one-line
// summary. Data = the newest weather_forecast snapshot the planner itself uses.
struct WeatherForecastCardView: View {
    @ObservedObject var fm = FirebaseManager.shared

    private let solarGold = Theme.solarGold
    private let loadBlue = Theme.loadBlue
    private let batteryGreen = Theme.batteryGreen

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH"
        return f
    }()
    private static let issuedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Next 24 hours from now
    private var next24: [ForecastHour] {
        let now = Date()
        return fm.forecastHours
            .filter { $0.time >= now.addingTimeInterval(-1800) }
            .prefix(24)
            .map { $0 }
    }

    /// WMO weather code -> SF Symbol (day/night aware)
    private func icon(for code: Int?, isDay: Bool) -> String {
        switch code ?? -1 {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67: return "cloud.rain.fill"
        case 71...77: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "questionmark.circle"
        }
    }

    var body: some View {
        if !next24.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("24H SOLAR FORECAST", systemImage: "cloud.sun.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(solarGold)
                        .tracking(1.5)
                    Spacer()
                    if let issued = fm.forecastIssuedAt {
                        Text("issued \(Self.issuedFormatter.string(from: issued))")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 4)

                // Mini legend: sun / cloud / rain each get their own visual channel
                HStack(spacing: 12) {
                    LegendItem(color: solarGold, label: "Irradiance")
                    LegendItem(color: Color.gray, label: "Cloud %", dashed: true)
                    LegendItem(color: loadBlue, label: "Rain")
                }
                .padding(.horizontal, 4)

                // Hourly irradiance bars + cloud-cover line — the shape of the coming solar day
                let maxGti = max(100.0, next24.compactMap { $0.gti }.max() ?? 100.0)
                Chart(next24) { h in
                    BarMark(
                        x: .value("Time", h.time, unit: .hour),
                        y: .value("GTI", h.gti ?? 0)
                    )
                    .foregroundStyle(
                        (h.precipMm ?? 0) > 0.2
                            ? LinearGradient(colors: [loadBlue.opacity(0.85), loadBlue.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [solarGold, solarGold.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                    )
                    .cornerRadius(2)

                    // Cloud cover: 0% hugs the floor (clear), 100% touches the top (overcast)
                    LineMark(
                        x: .value("Time", h.time, unit: .hour),
                        y: .value("Cloud", (h.cloudPct ?? 0) / 100.0 * maxGti),
                        series: .value("Series", "Cloud")
                    )
                    .foregroundStyle(Color.gray.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                    .interpolationMethod(.monotone)
                }
                .frame(height: 110)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(Color.white.opacity(0.15))
                        if let v = value.as(Double.self) {
                            AxisValueLabel {
                                Text("\(Int(v))")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.white.opacity(0.8))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(Color.white.opacity(0.15))
                        AxisValueLabel(format: .dateTime.hour(), anchor: .top)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                }

                // Precipitation mini-chart (mm/h) — hidden entirely on dry days
                let rainTotal24 = next24.compactMap { $0.precipMm }.reduce(0, +)
                if rainTotal24 > 0.05 {
                    Chart(next24) { h in
                        BarMark(
                            x: .value("Time", h.time, unit: .hour),
                            y: .value("Rain", h.precipMm ?? 0)
                        )
                        .foregroundStyle(loadBlue.opacity(0.8))
                        .cornerRadius(1)
                    }
                    .frame(height: 36)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { value in
                            if let v = value.as(Double.self) {
                                AxisValueLabel {
                                    Text(String(format: "%.1f", v))
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(loadBlue.opacity(0.9))
                                }
                            }
                        }
                    }
                    .chartXAxis(.hidden)
                }

                // 3-hourly icon + temperature strip
                HStack(spacing: 0) {
                    ForEach(Array(stride(from: 0, to: next24.count, by: 3)), id: \.self) { i in
                        let h = next24[i]
                        VStack(spacing: 3) {
                            Text(Self.hourFormatter.string(from: h.time))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.secondary)
                            Image(systemName: icon(for: h.weatherCode, isDay: h.isDay))
                                .font(.system(size: 13))
                                .symbolRenderingMode(.multicolor)
                            Text(h.tempC.map { String(format: "%.0f°", $0) } ?? "–")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.02))
                .cornerRadius(8)

                // One-line day summary
                let gtiTotal = next24.compactMap { $0.gti }.reduce(0, +) / 1000.0
                let rainTotal = next24.compactMap { $0.precipMm }.reduce(0, +)
                let temps = next24.compactMap { $0.tempC }
                HStack(spacing: 10) {
                    Label(String(format: "GTI %.1f kWh/m²", gtiTotal), systemImage: "sun.max")
                        .foregroundColor(solarGold)
                    Label(String(format: "%.1f mm", rainTotal), systemImage: "drop.fill")
                        .foregroundColor(rainTotal > 0.2 ? loadBlue : .secondary)
                    if let lo = temps.min(), let hi = temps.max() {
                        Label(String(format: "%.0f–%.0f°C", lo, hi), systemImage: "thermometer.medium")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .font(.system(size: 9.5, weight: .semibold))
            }
            .padding(16)
            .glassCardStyle(cornerRadius: 18)
        }
    }
}

// MARK: - Sub-components: Legend & Tooltip

/// Simple wrapping layout: lays subviews left-to-right, flowing onto new rows as needed.
/// Replaces the horizontal-scroll legend so every item is always visible.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Legend chip. When `onTap` is provided it acts as a visibility toggle:
/// active = normal, hidden = dimmed + strikethrough.
struct LegendItem: View {
    var color: Color
    var label: String
    var dashed: Bool = false
    var isActive: Bool = true
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            if dashed {
                RoundedRectangle(cornerRadius: 1)
                    .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: 10, height: 6)
            } else {
                Circle()
                    .fill(isActive ? color : Color.clear)
                    .overlay(Circle().stroke(color, lineWidth: 1))
                    .frame(width: 8, height: 8)
            }
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .strikethrough(!isActive, color: .secondary)
        }
        .opacity(isActive ? 1.0 : 0.4)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

struct TooltipView: View {
    var entry: TelemetryEntry
    var solarKwh: Double
    var loadKwh: Double
    var chargeKwh: Double
    var dischargeKwh: Double
    var importKwh: Double
    var exportKwh: Double
    var hidden: Set<String> = []

    // Line-matching color palette
    private let solarGold = Theme.solarGold
    private let loadBlue = Theme.loadBlue
    private let batteryGreen = Theme.batteryGreen
    private let gridPurple = Theme.gridPurple
    private let alertRed = Theme.alertRed
    private let pv1Cyan = Theme.pv1Cyan
    private let pv2Pink = Theme.pv2Pink

    private func vis(_ key: String) -> Bool { !hidden.contains(key) }

    private var timeString: String {
        guard let ts = entry.timestamp else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: ts)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(batteryGreen)
                Text("Time: \(timeString)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                let modeledSocVal = entry.modeled_soc ?? Double(entry.soc)
                HStack(spacing: 8) {
                    Text("BMS: \(entry.soc)%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(batteryGreen)
                    Text("🤖 AI: \(String(format: "%.1f%%", modeledSocVal))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                }
            }
            .padding(.horizontal, 4)

            // Section 1: Instantaneous Power — cells follow the legend's hide/show state
            if vis("solar") || vis("load") || vis("charge") || vis("discharge") || vis("import") || vis("export") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if vis("solar") {
                            tooltipCell(title: "SOLAR", valueView: Text(String(format: "%.2f kW", entry.solar_generation_kw)).foregroundColor(solarGold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if vis("load") {
                            tooltipCell(title: "LOAD", valueView: Text(String(format: "%.2f kW", entry.local_load_kw)).foregroundColor(loadBlue))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if vis("charge") || vis("discharge") {
                            let batNet = entry.charge_power_kw - entry.discharge_power_kw
                            tooltipCell(
                                title: "BATTERY",
                                valueView: Text(String(format: "%+.2f kW", batNet))
                                    .foregroundColor(batNet >= 0 ? batteryGreen : .orange)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if vis("import") || vis("export") {
                            let gridNet = entry.grid_import_kw - entry.grid_export_kw
                            tooltipCell(
                                title: "GRID",
                                valueView: Text(String(format: "%+.2f kW", gridNet))
                                    .foregroundColor(gridNet >= 0 ? gridPurple : alertRed)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(6)
                }
            }

            // Section 1b: Per-MPPT strings (power + voltage), shown when charted & data exists
            if (vis("pv1") || vis("pv2") || vis("v1") || vis("v2")),
               entry.pv1_power_kw != nil || entry.pv2_power_kw != nil || entry.pv1_voltage != nil || entry.pv2_voltage != nil {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if vis("pv1"), let p1 = entry.pv1_power_kw {
                            tooltipCell(title: "PV1 PWR", valueView: Text(String(format: "%.2f kW", p1)).foregroundColor(pv1Cyan))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if vis("v1"), let v1 = entry.pv1_voltage {
                            tooltipCell(title: "PV1 VOLT", valueView: Text(String(format: "%.0f V", v1)).foregroundColor(pv1Cyan.opacity(0.8)))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if vis("pv2"), let p2 = entry.pv2_power_kw {
                            tooltipCell(title: "PV2 PWR", valueView: Text(String(format: "%.2f kW", p2)).foregroundColor(pv2Pink))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if vis("v2"), let v2 = entry.pv2_voltage {
                            tooltipCell(title: "PV2 VOLT", valueView: Text(String(format: "%.0f V", v2)).foregroundColor(pv2Pink.opacity(0.8)))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(6)
                }
            }

            // Section 2: Cumulative Energy — cells follow the legend's hide/show state
            if vis("solar") || vis("load") || vis("charge") || vis("discharge") || vis("import") || vis("export") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        if vis("solar") {
                            tooltipCell(title: "SOLAR", valueView: Text(String(format: "%.2f kWh", solarKwh)).foregroundColor(solarGold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if vis("load") {
                            tooltipCell(title: "LOAD", valueView: Text(String(format: "%.2f kWh", loadKwh)).foregroundColor(loadBlue))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if vis("charge") || vis("discharge") {
                            tooltipCell(
                                title: "BATT CHG/DIS",
                                valueView: Text("\(Text(String(format: "%.1f", chargeKwh)).foregroundColor(batteryGreen))\(Text("/").foregroundColor(.secondary))\(Text(String(format: "%.1f", dischargeKwh)).foregroundColor(.orange))")
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if vis("import") || vis("export") {
                            tooltipCell(
                                title: "GRID IMP/EXP",
                                valueView: Text("\(Text(String(format: "%.1f", importKwh)).foregroundColor(gridPurple))\(Text("/").foregroundColor(.secondary))\(Text(String(format: "%.1f", exportKwh)).foregroundColor(alertRed))")
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(6)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(6)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func tooltipCell(title: String, valueView: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.secondary)
            valueView
                .font(.system(size: 9, weight: .bold, design: .rounded))
        }
    }
}
