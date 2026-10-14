import SwiftUI

struct EnergyFlowView: View {
    @ObservedObject var fm = FirebaseManager.shared
    @ObservedObject var live = FirebaseManager.shared.live
    @ObservedObject var wm = WeatherManager.shared
    
    // Theme Colors
    private let solarGold = Theme.solarGold
    private let batteryGreen = Theme.batteryGreen
    private let loadBlue = Theme.loadBlue
    private let gridPurple = Theme.gridPurple
    private let cardBg = Color(white: 0.08).opacity(0.85)

    static let syncTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Current inverter priority mode (from live telemetry's priorityChoose):
    /// 0 = Load First (normal daytime), 1 = Battery First (charge windows), 2 = Grid First.
    private var priorityInfo: (icon: String, label: String, color: Color)? {
        switch live.liveStatus?.data?.priorityChoose {
        case "0": return ("house.fill", "Load First", loadBlue)
        case "1": return ("battery.100.bolt", "Battery First", batteryGreen)
        case "2": return ("bolt.circle.fill", "Grid First", gridPurple)
        default: return nil
        }
    }

    /// The two parameters that govern the CURRENT mode's behaviour.
    private var modeDetailText: String? {
        switch live.liveStatus?.data?.priorityChoose {
        case "1":  // Battery First: where charging stops + how fast it charges
            guard live.chargeStopSoc != nil || live.chargePowerKw != nil else { return nil }
            return "Chg ↑\(live.chargeStopSoc ?? "–")% · \(live.chargePowerKw ?? "–")"
        case "0", "2":  // Load First (and Grid First): discharge floor + max discharge rate
            guard live.dischargeStopSoc != nil || live.dischargePowerKw != nil else { return nil }
            return "Dis ↓\(live.dischargeStopSoc ?? "–")% · \(live.dischargePowerKw ?? "–")"
        default:
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("LIVE ENERGY FLOW", systemImage: "bolt.horizontal.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(batteryGreen)
                    .tracking(1.5)
                Spacer()
                
                if live.liveStatus?.last_updated != nil {
                    Text("LIVE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(3)
                }
            }
            .padding(.horizontal, 4)
            
            // Flow Diagram Space
            ZStack {
                // Connection Paths with moving dot animations
                FlowLine(from: CGPoint(x: 150, y: 30), to: CGPoint(x: 150, y: 125), active: solarPower > 0, color: solarGold, reverse: false)
                
                // Battery Connection Flow (Center to Left or Left to Center)
                if isCharging {
                    FlowLine(from: CGPoint(x: 150, y: 125), to: CGPoint(x: 50, y: 125), active: true, color: batteryGreen, reverse: false)
                } else {
                    FlowLine(from: CGPoint(x: 50, y: 125), to: CGPoint(x: 150, y: 125), active: dischargePower > 0, color: batteryGreen, reverse: false)
                }
                
                // Home Load Connection Flow (Center to Right)
                FlowLine(from: CGPoint(x: 150, y: 125), to: CGPoint(x: 250, y: 125), active: loadPower > 0, color: loadBlue, reverse: false)
                
                // Grid Connection Flow (Center to Bottom or Bottom to Center)
                if isExporting {
                    FlowLine(from: CGPoint(x: 150, y: 125), to: CGPoint(x: 150, y: 220), active: true, color: gridPurple, reverse: false)
                } else {
                    FlowLine(from: CGPoint(x: 150, y: 220), to: CGPoint(x: 150, y: 125), active: gridImport > 0, color: gridPurple, reverse: false)
                }
                
                // Tesla Connection Flow (From top of Load node to bottom of Tesla node)
                let teslaConnected = fm.live.teslaStatus?.is_connected == true
                let teslaCharging = fm.live.teslaStatus?.charging_state == "Charging"
                let teslaKw = fm.live.teslaStatus?.charger_power_kw ?? 0.0
                let teslaSoc = fm.live.teslaStatus?.battery_level ?? 0
                if teslaConnected && teslaCharging {
                    // Load top: (250, 97) -> Tesla bottom: (250, 58)
                    FlowLine(from: CGPoint(x: 250, y: 97), to: CGPoint(x: 250, y: 58), active: true, color: Color(red: 0.86, green: 0.15, blue: 0.15), reverse: false)
                }
                
                // Nodes
                
                // 1. Inverter (Center) — same size as Battery/Load so all three icons read as one row
                NodeView(title: "Inverter", icon: "bolt.shield.fill", valStr: "", color: .white.opacity(0.85), size: 56)
                    .position(x: 150, y: 125)
                
                // 2. Solar PV (Top) — real weather icon
                NodeView(title: wm.weather.description,
                         icon: wm.weather.icon,
                         valStr: String(format: "%.2f kW", solarPower),
                         color: wm.weather.color,
                         size: 56)
                    .position(x: 150, y: 30)
                
                // 3. Battery (Left)
                let latestEntry = live.telemetryHistory.last
                let modeledSocVal = Double(live.liveStatus?.data?.modeled_soc ?? "") ?? (latestEntry?.modeled_soc ?? Double(batterySoc))
                BatteryNodeView(soc: batterySoc, modeledSoc: modeledSocVal, chargeKw: chargePower, dischargeKw: dischargePower, color: batteryGreen)
                    .position(x: 50, y: 125)
                
                // 4. Home Load (Right)
                NodeView(title: "Load", icon: "house.fill", valStr: String(format: "%.2f kW", loadPower), color: loadBlue, size: 56)
                    .position(x: 250, y: 125)
                
                // 5. Tesla EV (Above Load, size 56 matching other nodes) — Deep Crimson Glow
                if teslaConnected {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(teslaCharging ? Color(red: 0.5, green: 0.11, blue: 0.11).opacity(0.4) : Color.white.opacity(0.08))
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Circle()
                                        .stroke(teslaCharging ? Color(red: 0.86, green: 0.15, blue: 0.15).opacity(0.6) : Color.white.opacity(0.25), lineWidth: 1.5)
                                )
                            Text("\(teslaSoc)%")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(teslaCharging ? Color(red: 0.97, green: 0.44, blue: 0.44) : Color.white.opacity(0.9))
                        }
                        Text(fm.live.teslaStatus?.car_name ?? "Tesla")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(teslaCharging ? String(format: "⚡ %.1f kW", teslaKw) : "Standby")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(teslaCharging ? Color(red: 0.97, green: 0.44, blue: 0.44) : Color.white.opacity(0.45))
                    }
                    .position(x: 250, y: 30)
                }
                
                // 6. Grid (Bottom)
                GridNodeView(importKw: gridImport, exportKw: gridExport, color: gridPurple)
                    .position(x: 150, y: 220)
            }
            .frame(width: 300, height: 275)
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .center)
            // Sync freshness sits in the diagram's empty bottom-right corner — the node
            // layout is a diamond, so the corners are free space. No extra row needed.
            .overlay(alignment: .bottomTrailing) {
                if let lastUpdated = live.liveStatus?.last_updated {
                    // Freshness chip: colored health dot + auto-ticking relative time.
                    // Green = healthy 5-min cycle; orange = a beat late; red = sync stalled.
                    let age = Date().timeIntervalSince(lastUpdated)
                    let dotColor: Color = age < 360 ? batteryGreen : (age < 900 ? .orange : .red)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 5, height: 5)
                        Text("\(Text(lastUpdated, style: .relative)) ago")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.04)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.06), lineWidth: 0.5))
                    // Baseline-align with the left block: chip text sits 3pt above the
                    // capsule bottom, so 1pt outer + 3pt inner = the left block's 4pt.
                    .padding(.trailing, 4)
                    .padding(.bottom, 1)
                }
            }
            // Inverter management state fills the matching bottom-left corner:
            // current priority mode + the two SoC boundaries governing it.
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    if let (icon, label, color) = priorityInfo {
                        HStack(spacing: 3) {
                            Image(systemName: icon)
                                .font(.system(size: 8))
                                .foregroundColor(color)
                            Text(label)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(color)
                        }
                    }
                    // Mode-contextual boundary line: show actual charge/discharge power limits (%)
                    // from growatt_live. Fallback "–" (not "100") so a cold-start race condition
                    // is visible instead of silently showing a misleading 100%.
                    let disCmd = live.liveStatus?.data?.disChargePowerCommand
                    let chgCmd = live.liveStatus?.data?.chargePowerCommand
                    let disPct  = Int(disCmd ?? "") ?? 100
                    let chgPct  = Int(chgCmd ?? "") ?? 100
                    let disDisplay = disCmd.map { "\($0)%" } ?? "–%"
                    let chgDisplay = chgCmd.map { "\($0)%" } ?? "–%"
                    let isDisColdActive = disPct < 100
                    let isChgColdActive = chgPct < 100
                    Text("⚡ Disch: \(disDisplay)")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(isDisColdActive ? Color.orange : Color.secondary.opacity(0.85))
                    Text("🔌 Chg: \(chgDisplay)")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(isChgColdActive ? Color.orange : Color.secondary.opacity(0.85))
                }
                .padding(.leading, 4)
                .padding(.bottom, 4)
            }
        }
        .padding()
        .background(SoCCardBackground(soc: batterySoc))
        .glassCardStyle(cornerRadius: 18)
        .onAppear {
            wm.fetchIfNeeded(timezone: fm.settings.timezone)
        }
        .onChange(of: fm.settings.timezone) { _, newTZ in
            wm.fetch(timezone: newTZ)
        }
    }
    // --- Helper telemetries derived from live.liveStatus ---
    
    private var solarPower: Double {
        if let pvStr = live.liveStatus?.data?.ppv {
            return Double(pvStr) ?? 0.0
        }
        return 0.0
    }
    
    private var batterySoc: Int {
        if let socStr = live.liveStatus?.data?.SOC {
            return Int(socStr) ?? 0
        }
        return 0
    }
    
    private var chargePower: Double {
        if let val = live.liveStatus?.data?.chargePower {
            return Double(val) ?? 0.0
        }
        return 0.0
    }
    
    private var dischargePower: Double {
        if let val = live.liveStatus?.data?.dischargePower {
            return Double(val) ?? 0.0
        }
        return 0.0
    }
    
    private var loadPower: Double {
        if let val = live.liveStatus?.data?.localLoad {
            return Double(val) ?? 0.0
        }
        return 0.0
    }
    
    private var gridImport: Double {
        if let val = live.liveStatus?.data?.gridImport {
            return Double(val) ?? 0.0
        }
        return 0.0
    }
    
    private var gridExport: Double {
        if let val = live.liveStatus?.data?.gridExport {
            return Double(val) ?? 0.0
        }
        return 0.0
    }
    
    private var isCharging: Bool {
        return chargePower > 0
    }
    
    private var isExporting: Bool {
        return gridExport > 0
    }
}

/// Ambient background for the LIVE ENERGY FLOW card: a soft glow that rises from the
/// bottom of the card, taller and slightly stronger the higher the battery's SoC — colored
/// red/gold/green using the same 20% threshold the battery icon elsewhere already uses
/// (`soc > 20`), so it's one consistent health signal rather than a second, competing color
/// language on the same screen. Deliberately has no hard edge anywhere: rather than clipping
/// a rectangle to a fill height (which reads as a literal gauge with a visible waterline),
/// the gradient's own far endpoint moves with SoC, so it's always a single smooth fade from
/// the bottom to nothing — just mood lighting, not a level indicator. Applied via
/// `.background()` before `.glassCardStyle()` so it sits behind the diagram and text.
private struct SoCCardBackground: View {
    var soc: Int

    private var fraction: CGFloat {
        CGFloat(max(0, min(100, soc))) / 100.0
    }

    private var tint: Color {
        switch soc {
        case ..<20: return Theme.alertRed
        case 20..<50: return Theme.solarGold
        default: return Theme.batteryGreen
        }
    }

    var body: some View {
        LinearGradient(
            colors: [tint.opacity(0.22), tint.opacity(0.0)],
            startPoint: .bottom,
            endPoint: UnitPoint(x: 0.5, y: 1.0 - fraction)
        )
        .animation(.easeInOut(duration: 0.6), value: soc)
    }
}

// --- Node Views ---

// Every node here is laid out as: fixed-size icon circle, with its caption (title + optional
// kW value) hanging below as an .overlay rather than a VStack sibling. An overlay doesn't
// change the reported size of the view it's attached to, so `.position(x, y)` in the parent
// ZStack always centers the ICON itself — regardless of whether the caption below is one line
// (Inverter) or two (Battery/Load/Grid). That's also what makes the FlowLine endpoints (which
// use these same x/y coordinates) land exactly on the icon's center rather than a few points off.
private let flowCaptionGap: CGFloat = 4

struct NodeView: View {
    var title: String
    var icon: String
    var valStr: String
    var color: Color
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.15), radius: 6)

            Circle()
                .stroke(color.opacity(0.35), lineWidth: 1.5)
                .frame(width: size, height: size)

            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundColor(color)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .top) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)

                if !valStr.isEmpty {
                    Text(valStr)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .fixedSize()
            .offset(y: size + flowCaptionGap)
        }
    }
}

struct BatteryNodeView: View {
    var soc: Int
    var modeledSoc: Double?
    var chargeKw: Double
    var dischargeKw: Double
    var color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 56, height: 56)

            Circle()
                .trim(from: 0, to: CGFloat(soc) / 100.0)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 53, height: 53)
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Image(systemName: soc > 20 ? "battery.100" : "battery.25")
                    .font(.system(size: 13))
                    .foregroundColor(color)
                Text("\(soc)%")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 56, height: 56)
        .overlay(alignment: .top) {
            VStack(spacing: 3) {
                Text("Battery")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)

                let aiSocVal = modeledSoc ?? Double(soc)
                Text(String(format: "🤖 AI %.1f%%", aiSocVal))
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.22, green: 0.74, blue: 0.97))

                if chargeKw > 0 {
                    Text(String(format: "+%.2f kW", chargeKw))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(color)
                } else if dischargeKw > 0 {
                    Text(String(format: "-%.2f kW", dischargeKw))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                } else {
                    Text("Idle")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .fixedSize()
            .offset(y: 56 + flowCaptionGap)
        }
    }
}

struct GridNodeView: View {
    var importKw: Double
    var exportKw: Double
    var color: Color
    
    private var activeColor: Color {
        if importKw > 0 {
            return Color(red: 0.94, green: 0.27, blue: 0.27) // Red for importing
        } else if exportKw > 0 {
            return Color(red: 0.96, green: 0.62, blue: 0.04) // Gold/Orange for exporting
        } else {
            return Color.secondary.opacity(0.6)
        }
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 56, height: 56)
                .shadow(color: activeColor.opacity(importKw > 0 || exportKw > 0 ? 0.35 : 0.0), radius: 8)

            Circle()
                .stroke(activeColor.opacity(importKw > 0 || exportKw > 0 ? 0.8 : 0.25), lineWidth: 2)
                .frame(width: 56, height: 56)

            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(activeColor)
        }
        .frame(width: 56, height: 56)
        .overlay(alignment: .top) {
            VStack(spacing: 4) {
                Text("Grid Utility")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)

                if importKw > 0 {
                    Text(String(format: "Import %.2f kW", importKw))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(activeColor)
                } else if exportKw > 0 {
                    Text(String(format: "Export %.2f kW", exportKw))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(activeColor)
                } else {
                    Text("Balanced")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .fixedSize()
            .offset(y: 56 + flowCaptionGap)
        }
    }
}

// --- Animated Flowing Path Line ---

struct FlowLine: View {
    var from: CGPoint
    var to: CGPoint
    var active: Bool
    var color: Color
    var reverse: Bool
    
    @State private var phase: Double = 0.0
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Line path
                Path { path in
                    path.move(to: from)
                    path.addLine(to: to)
                }
                .stroke(active ? color.opacity(0.25) : Color.white.opacity(0.04), lineWidth: active ? 2.5 : 1.5)
                
                if active {
                    // Flowing dot
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .shadow(color: color, radius: 3)
                        .position(pointAlongPath(from: from, to: to, progress: phase))
                        .animation(active ? Animation.linear(duration: 1.8).repeatForever(autoreverses: false) : nil, value: phase)
                }
            }
            .onAppear {
                if active {
                    startAnimation()
                }
            }
            .onChange(of: active) { _, isActive in
                if isActive {
                    startAnimation()
                } else {
                    stopAnimation()
                }
            }
        }
    }
    
    private func startAnimation() {
        phase = 0.0
        DispatchQueue.main.async {
            phase = 1.0
        }
    }
    
    private func stopAnimation() {
        phase = 0.0
    }
    
    private func pointAlongPath(from: CGPoint, to: CGPoint, progress: Double) -> CGPoint {
        let actualProgress = reverse ? (1.0 - progress) : progress
        return CGPoint(
            x: from.x + (to.x - from.x) * CGFloat(actualProgress),
            y: from.y + (to.y - from.y) * CGFloat(actualProgress)
        )
    }
}
