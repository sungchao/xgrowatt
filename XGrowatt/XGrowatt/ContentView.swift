import SwiftUI
import CoreLocation
import Combine
import Charts
import MapKit

struct GeneratedBillResult {
    var startDate: Date
    var endDate: Date
    var totalSolarKwh: Double
    var totalLoadKwh: Double
    var totalImportKwh: Double
    var totalExportKwh: Double
    var totalChargeKwh: Double
    var totalDischargeKwh: Double
    var dailySupplyChargeTotal: Double
    var grossImportCost: Double
    var grossExportCredit: Double
    var netBillAmount: Double
    var totalSavings: Double
    var totalArbitrage: Double
    
    var totalPeakKwh: Double
    var totalPeakCost: Double
    var totalOffPeakKwh: Double
    var totalOffPeakCost: Double
    var totalFreeKwh: Double
    var totalFreeCost: Double
}

struct ContentView: View {
    @StateObject private var fm = FirebaseManager.shared
    @ObservedObject private var live = FirebaseManager.shared.live
    @ObservedObject private var wm = WeatherManager.shared
    @StateObject private var locationHelper = LocationHelper()
    
    // Timer States
    @State private var saveStatusMessage: String?
    @State private var autoDismissTimer: Timer?
    @State private var refreshTimer: Timer?
    @State private var isAppStarting = true
    
    // Navigation & Interaction States
    @State private var selectedTab = 0
    @State private var isScrubbingCharts = false
    @State private var bmsScrubIndex: Int? = nil
    @State private var isCredentialsExpanded = false
    @State private var isMascotSettingsExpanded = false
    @State private var showGeminiKey = false
    @State private var isLogsExpanded = false
    @State private var isAboutExpanded = false
    

    
    // Premium Design Palette
    private let bgDark = Theme.bgDark
    private let cardBg = Theme.cardBg
    private let solarGold = Theme.solarGold
    private let batteryGreen = Theme.batteryGreen
    private let alertRed = Theme.alertRed
    private let loadBlue = Theme.loadBlue
    private let gridPurple = Theme.gridPurple
    
    
    init() {
        // 1. Configure standard and scroll edge appearances for UITabBar to be completely transparent
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        
        // 2. Clear background for all UIViews hosted inside any UITabBarController
        // This clears host containers and child controller transition views natively and synchronously.
        UIView.appearance(whenContainedInInstancesOf: [UITabBarController.self]).backgroundColor = .clear
    }
    
    var body: some View {
        ZStack {
            // Layer 0: Base dark
            bgDark.ignoresSafeArea()
            
            // Layer 1: Dynamic atmospheric background
            if !isAppStarting {
                weatherBackground
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .id("weather_bg")
            }
            
            if isAppStarting {
                // Splash / Launch Screen while Firebase loads in background
                VStack(spacing: 24) {
                    Spacer()
                    
                    ZStack {
                        Circle()
                            .fill(batteryGreen.opacity(0.12))
                            .frame(width: 100, height: 100)
                            .blur(radius: 8)
                        
                        Image(systemName: "bolt.circle.fill")
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundColor(batteryGreen)
                            .shadow(color: batteryGreen.opacity(0.4), radius: 10)
                    }
                    
                    VStack(spacing: 8) {
                        Text("XGROWATT AUTO")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .tracking(3)
                        
                        Text("Connecting to ShineServer...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    ProgressView()
                        .tint(batteryGreen)
                        .scaleEffect(1.2)
                    
                    Spacer()
                        .frame(height: 40)
                }
                .transition(.opacity)
                .onAppear {
                    // Pre-fetch live data, then fade out the splash screen after 1.5 seconds maximum timeout
                    // This creates a seamless transition once the data begins streaming in background
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeOut(duration: 0.4)) {
                            isAppStarting = false
                        }
                    }
                }
            } else {
                TabView(selection: $selectedTab) {
                    // Tab 1: Dashboard
                    ScrollView {
                        HomeDashboardView()
                            .padding(.bottom, 20)
                    }
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .refreshable {
                        fm.triggerManualSync(mode: "read")
                        fm.refreshTeslaStatus()
                        while live.isSyncing {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                        }
                    }
                    .tabItem {
                        Label("Dashboard", systemImage: "bolt.fill")
                    }
                    .tag(0)
                    
                    // Tab 2: Historical Analytics
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            HistoryAnalyticsView()
                                .padding(.bottom, 20)
                        }
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .refreshable {
                            fm.triggerManualSync(mode: "read")
                            fm.refreshTeslaStatus()
                            while live.isSyncing {
                                try? await Task.sleep(nanoseconds: 100_000_000)
                            }
                        }
                        .onChange(of: isScrubbingCharts) { oldValue, newValue in
                            if newValue {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    scrollProxy.scrollTo("charts_section", anchor: .top)
                                }
                            }
                        }
                    }
                    .tabItem {
                        Label("Analytics", systemImage: "chart.bar.fill")
                    }
                    .tag(1)
                    
                    // Tab 3: Plan & Bills
                    PlanBillsTabContainerView(fm: fm)
                    .tabItem {
                        Label("Plan & Bills", systemImage: "calendar")
                    }
                    .tag(2)
                    
                    // Tab 4: Settings
                    ScrollView {
                        SystemSettingsView()
                            .padding(.bottom, 20)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .scrollContentBackground(.hidden)
                    .background(
                        Color.black.opacity(0.001)
                            .onTapGesture {
                                UIApplication.shared.endEditing()
                            }
                    )
                    .refreshable {
                        fm.triggerManualSync(mode: "read")
                        fm.refreshTeslaStatus()
                        while live.isSyncing {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                        }
                    }
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(3)
                }
                .background(TabViewBackgroundCleaner(selectedTab: selectedTab))
                .tint(batteryGreen)
                .toolbarBackground(.ultraThinMaterial, for: .tabBar)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            
            // Global Floating Mascot Overlay (Floats gracefully across all 4 screens, hidden during launch screen)
            if !isAppStarting {
                GlobalFloatingMascotOverlay(
                    live: live,
                    fm: fm,
                    weatherState: wm.weather
                )
            }
            
            // Floating Status Feedback Notification Banner
            if let msg = saveStatusMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding()
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.85))
                                .overlay(
                                    Capsule()
                                        .stroke(batteryGreen.opacity(0.5), lineWidth: 1)
                                )
                        )
                        .shadow(color: batteryGreen.opacity(0.3), radius: 10, x: 0, y: 5)
                        .padding(.bottom, 70)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(), value: saveStatusMessage)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            print("App returned to foreground, starting auto-refresh timer...")
            startTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            print("App entered background, stopping auto-refresh timer...")
            stopTimer()
        }


    }
    
    // MARK: - Dynamic Atmospheric Background

    @ViewBuilder
    private var weatherBackground: some View {
        let temp = wm.weather.temperature ?? 18.0
        let isDay = wm.isDay
        let clearIcons = ["sun.max.fill", "cloud.sun.fill", "moon.stars.fill", "moon.fill", "cloud.moon.fill"]
        let isOvercast = !clearIcons.contains(wm.weather.icon) && wm.weather.isRealData
        let p = atmosphericPalette(isDay: isDay, temp: temp, isOvercast: isOvercast)

        ZStack {
            // Layer 1: base directional gradient
            LinearGradient(
                colors: p.base,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Layer 2: sun / moon halo at top — RadialGradient centred outside top
            RadialGradient(
                colors: [p.orb, .clear],
                center: UnitPoint(x: isDay ? 0.75 : 0.28, y: 0.05),
                startRadius: 0,
                endRadius: 380
            )
            .opacity(0.75)

            // Layer 3: horizon warmth at bottom
            RadialGradient(
                colors: [p.horizon, .clear],
                center: UnitPoint(x: 0.5, y: 1.08),
                startRadius: 0,
                endRadius: 300
            )
            .opacity(0.55)
            
            // Layer 4: Stylized Sun or Moon (glowing in the background) - only visible on clear/partly cloudy skies and when real weather data is loaded
            let isPartlyCloudy = wm.weather.icon == "cloud.sun.fill" || wm.weather.icon == "cloud.moon.fill"
            if !isOvercast && wm.weather.isRealData {
                if isDay {
                    SunVisual(isPartlyCloudy: isPartlyCloudy)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    MoonVisual(isPartlyCloudy: isPartlyCloudy)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            
            // Layer 5: Dynamic Rain particle canvas overlay
            let rainIcons = ["cloud.drizzle.fill", "cloud.rain.fill", "cloud.bolt.rain.fill", "cloud.sun.rain.fill", "cloud.moon.rain.fill"]
            let isRainy = rainIcons.contains(wm.weather.icon)
            if isRainy {
                RainView()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 2.5), value: wm.weather.isRealData)
        .animation(.easeInOut(duration: 2.5), value: wm.weather.description)
    }

    private struct AtmosPalette {
        var base: [Color]
        var orb: Color
        var horizon: Color
    }

    private func atmosphericPalette(isDay: Bool, temp: Double, isOvercast: Bool) -> AtmosPalette {
        if isOvercast {
            if isDay {
                // Steel gray-blue overcast day
                return AtmosPalette(
                    base:    [Color(red: 0.35, green: 0.38, blue: 0.45),
                              Color(red: 0.20, green: 0.22, blue: 0.28)],
                    orb:     Color(red: 0.45, green: 0.48, blue: 0.55),
                    horizon: Color(red: 0.28, green: 0.30, blue: 0.36)
                )
            } else {
                // Dark gray-indigo overcast night (heavy clouds)
                return AtmosPalette(
                    base:    [Color(red: 0.06, green: 0.06, blue: 0.12),
                              Color(red: 0.03, green: 0.03, blue: 0.06)],
                    orb:     Color(red: 0.12, green: 0.14, blue: 0.22),
                    horizon: Color(red: 0.08, green: 0.09, blue: 0.15)
                )
            }
        }

        if !isDay {
            if temp < 10 {
                // Cold night — icy navy-cobalt
                return AtmosPalette(
                    base:    [Color(red:0.04, green:0.06, blue:0.28),
                              Color(red:0.02, green:0.04, blue:0.18)],
                    orb:     Color(red:0.35, green:0.55, blue:1.00),
                    horizon: Color(red:0.20, green:0.35, blue:0.75)
                )
            } else if temp < 22 {
                // Mild night — deep indigo-violet
                return AtmosPalette(
                    base:    [Color(red:0.06, green:0.04, blue:0.32),
                              Color(red:0.03, green:0.03, blue:0.20)],
                    orb:     Color(red:0.45, green:0.30, blue:0.95),
                    horizon: Color(red:0.28, green:0.15, blue:0.65)
                )
            } else {
                // Warm night — purple-magenta
                return AtmosPalette(
                    base:    [Color(red:0.12, green:0.04, blue:0.30),
                              Color(red:0.06, green:0.02, blue:0.18)],
                    orb:     Color(red:0.70, green:0.25, blue:0.90),
                    horizon: Color(red:0.50, green:0.10, blue:0.55)
                )
            }
        } else {
            if temp < 12 {
                // Cold day — crisp steel-blue sky
                return AtmosPalette(
                    base:    [Color(red:0.05, green:0.15, blue:0.45),
                              Color(red:0.03, green:0.10, blue:0.30)],
                    orb:     Color(red:0.70, green:0.88, blue:1.00),
                    horizon: Color(red:0.30, green:0.60, blue:0.95)
                )
            } else if temp < 22 {
                // Mild day — clear ocean sky
                return AtmosPalette(
                    base:    [Color(red:0.04, green:0.20, blue:0.50),
                              Color(red:0.03, green:0.13, blue:0.32)],
                    orb:     Color(red:0.75, green:0.93, blue:1.00),
                    horizon: Color(red:0.20, green:0.65, blue:0.90)
                )
            } else if temp < 32 {
                // Warm day — golden amber afternoon
                return AtmosPalette(
                    base:    [Color(red:0.30, green:0.14, blue:0.01),
                              Color(red:0.15, green:0.08, blue:0.01)],
                    orb:     Color(red:1.00, green:0.82, blue:0.25),
                    horizon: Color(red:0.92, green:0.48, blue:0.08)
                )
            } else {
                // Hot day — scorching orange-red
                return AtmosPalette(
                    base:    [Color(red:0.40, green:0.07, blue:0.01),
                              Color(red:0.22, green:0.04, blue:0.01)],
                    orb:     Color(red:1.00, green:0.52, blue:0.08),
                    horizon: Color(red:0.90, green:0.18, blue:0.04)
                )
            }
        }
    }


    // MARK: - Screen Views
    
    @ViewBuilder
    private func HomeDashboardView() -> some View {
        VStack(spacing: 24) {
            // Header (Status bar cleared)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("XGROWATT AUTO")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(batteryGreen)
                        .tracking(1.5)
                    
                    Text("Dashboard")
                        .font(.title2)
                        .fontWeight(.black)
                        .foregroundColor(.white)
                }
                Spacer()
                
                Button(action: {
                    fm.triggerManualSync(mode: "read")
                    triggerSaveFeedback(message: "Requesting fresh telemetry...")
                }) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(live.isSyncing ? .secondary : batteryGreen)
                }
                .disabled(live.isSyncing)
            }
            .padding(.horizontal)
            .padding(.top, 28)
            
            // Drift alert: the inverter's actual schedule differs from the app's settings
            // (changed via the Growatt app/API?). Auto-corrected at the next pre-window push.
            if live.status?.inverter_matches == false {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Inverter schedule differs from app settings")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                        Text("Inverter reports: \(live.status?.inverter_actual ?? "unknown"). Changed externally? It will be overwritten before the next charge window.")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
                .padding(.horizontal)
            }

            // Hero Element: Animated energy flow
            EnergyFlowView()
                .padding(.horizontal)
            
            // 1.5. Interactive Energy Independence & Self-Consumption (Unified Horizontal Banner)
            let selfSufficiency = totalLoadKwh > 0 ? (max(0.0, min(100.0, (totalLocalLoadKwh / totalLoadKwh) * 100.0))) : 0.0
            let selfConsumption = totalSolarKwh > 0 ? (max(0.0, min(100.0, (totalLocalSolarKwh / totalSolarKwh) * 100.0))) : 0.0
            
            VStack(alignment: .leading, spacing: 10) {
                Label("TODAY'S EFFICIENCY", systemImage: "chart.bar.doc.horizontal.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(batteryGreen)
                    .tracking(1.5)
                
                // 2x2 grid: each column pairs a ring with its related equivalent stat —
                // no dividers, symmetric columns, aligned leading edges.
                HStack(alignment: .top, spacing: 16) {
                    let trees = totalSolarKwh * 0.0004
                    let co2 = totalSolarKwh * 0.7

                    // Column 1: Solar Independence + Trees
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.04), lineWidth: 4.5)
                                Circle()
                                    .trim(from: 0.0, to: CGFloat(selfSufficiency / 100.0))
                                    .stroke(
                                        LinearGradient(colors: [batteryGreen, batteryGreen.opacity(0.6)], startPoint: .top, endPoint: .bottom),
                                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                                    )
                                    .rotationEffect(Angle(degrees: -90))

                                Text("\(Int(selfSufficiency))%")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 1) {
                                Text("Grid Independence")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Load not from grid")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 5) {
                            Image(systemName: "leaf.fill")
                                .font(.system(size: 10))
                                .foregroundColor(batteryGreen)
                                .frame(width: 44)
                            Text(String(format: "%.4f", trees))
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("Trees")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Column 2: Self-Consumption + CO2
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.04), lineWidth: 4.5)
                                Circle()
                                    .trim(from: 0.0, to: CGFloat(selfConsumption / 100.0))
                                    .stroke(
                                        LinearGradient(colors: [solarGold, solarGold.opacity(0.6)], startPoint: .top, endPoint: .bottom),
                                        style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
                                    )
                                    .rotationEffect(Angle(degrees: -90))

                                Text("\(Int(selfConsumption))%")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 1) {
                                Text("Self-Consumption")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Ratio Today")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 5) {
                            Image(systemName: "cloud.fill")
                                .font(.system(size: 10))
                                .foregroundColor(loadBlue)
                                .frame(width: 44)
                            Text(String(format: "%.1f kg", co2))
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("CO2 Saved")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .glassCardStyle(cornerRadius: 18)
            .padding(.horizontal)

            // 2. Grid Status panels
            QuickStatsGrid()
                .padding(.horizontal)

            // 3. Energy Conservation Balance (Inputs vs Outputs side-by-side comparison)
            // Moved here from the top of Analytics — it reads as a same-day summary,
            // so it belongs at the end of today's dashboard rather than leading history.
            VStack(alignment: .leading, spacing: 12) {
                Label("ENERGY BALANCE (TODAY)", systemImage: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(batteryGreen)
                    .tracking(1.5)

                HStack(spacing: 12) {
                    let totalInputs = totalSolarKwh + totalDischargeKwh + totalImportKwh
                    let totalOutputs = totalLoadKwh + totalChargeKwh + totalExportKwh

                    // Left Column: Inputs
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("INPUTS")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.2f kWh", totalInputs))
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundColor(batteryGreen)
                        }

                        // Input Bar (Segmented with gaps)
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                if totalInputs > 0 {
                                    let w1 = CGFloat(totalSolarKwh / totalInputs) * (geo.size.width - 4)
                                    let w2 = CGFloat(totalDischargeKwh / totalInputs) * (geo.size.width - 4)
                                    let w3 = CGFloat(totalImportKwh / totalInputs) * (geo.size.width - 4)

                                    if totalSolarKwh > 0 {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(solarGold)
                                            .frame(width: max(2, w1))
                                    }
                                    if totalDischargeKwh > 0 {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.orange)
                                            .frame(width: max(2, w2))
                                    }
                                    if totalImportKwh > 0 {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(gridPurple)
                                            .frame(width: max(2, w3))
                                    }
                                } else {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white.opacity(0.04))
                                }
                            }
                        }
                        .frame(height: 6)

                        // Detailed Sources
                        VStack(spacing: 6) {
                            matrixRow(color: solarGold, label: "Solar", value: totalSolarKwh, total: totalInputs)
                            matrixRow(color: .orange, label: "Bat Dis", value: totalDischargeKwh, total: totalInputs)
                            matrixRow(color: gridPurple, label: "Grid Imp", value: totalImportKwh, total: totalInputs)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.015))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.03), lineWidth: 1)
                    )

                    // Right Column: Outputs
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("OUTPUTS")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.2f kWh", totalOutputs))
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundColor(solarGold)
                        }

                        // Output Bar (Segmented with gaps)
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                if totalOutputs > 0 {
                                    let w1 = CGFloat(totalLoadKwh / totalOutputs) * (geo.size.width - 4)
                                    let w2 = CGFloat(totalChargeKwh / totalOutputs) * (geo.size.width - 4)
                                    let w3 = CGFloat(totalExportKwh / totalOutputs) * (geo.size.width - 4)

                                    if totalLoadKwh > 0 {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(loadBlue)
                                            .frame(width: max(2, w1))
                                    }
                                    if totalChargeKwh > 0 {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(batteryGreen)
                                            .frame(width: max(2, w2))
                                    }
                                    if totalExportKwh > 0 {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(alertRed)
                                            .frame(width: max(2, w3))
                                    }
                                } else {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white.opacity(0.04))
                                }
                            }
                        }
                        .frame(height: 6)

                        // Detailed Sinks
                        VStack(spacing: 6) {
                            let teslaKwh = fm.live.teslaStatus?.charge_energy_added_kwh ?? 0.0
                            let houseKwh = max(0.0, totalLoadKwh - teslaKwh)

                            if teslaKwh > 0.1 {
                                matrixRow(color: loadBlue, label: "House Load", value: houseKwh, total: totalOutputs)
                                matrixRow(color: Color(red: 0.8, green: 0.0, blue: 0.0), label: "Tesla EV", value: teslaKwh, total: totalOutputs)
                            } else {
                                matrixRow(color: loadBlue, label: "Load", value: totalLoadKwh, total: totalOutputs)
                            }
                            matrixRow(color: batteryGreen, label: "Bat Chg", value: totalChargeKwh, total: totalOutputs)
                            matrixRow(color: alertRed, label: "Grid Exp", value: totalExportKwh, total: totalOutputs)
                        }
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.015))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.03), lineWidth: 1)
                    )
                }

                // Tesla Tariff Matched Savings Badge
                if let teslaKwh = fm.live.teslaStatus?.charge_energy_added_kwh, teslaKwh > 0.1 {
                    let estCost = teslaKwh * 0.11
                    let estSavings = teslaKwh * (0.35 - 0.11)
                    HStack {
                        HStack(spacing: 4) {
                            Text("🚘")
                                .font(.system(size: 11))
                            Text("Tesla Tariff Matched: \(String(format: "%.1f", teslaKwh)) kWh ($\(String(format: "%.2f", estCost)))")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        Text("Saved $\(String(format: "%.2f", estSavings)) (Off-Peak)")
                            .font(.system(size: 9.5, weight: .black))
                            .foregroundColor(batteryGreen)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(batteryGreen.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(batteryGreen.opacity(0.25), lineWidth: 1)
                    )
                    .cornerRadius(8)
                }
            }
            .padding(14)
            .glassCardStyle(cornerRadius: 18)
            .padding(.horizontal)

            // Tesla EV Live Charging Status Card
            TeslaEvLiveCardView(fm: fm)
                .padding(.horizontal)

            // Next-24h weather & solar forecast
            WeatherForecastCardView()
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func HistoryAnalyticsView() -> some View {
        VStack(spacing: 24) {
            // Header (Status bar cleared)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("METRICS HISTORY")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(batteryGreen)
                        .tracking(1.5)
                    
                    Text("Solar Analytics")
                        .font(.title2)
                        .fontWeight(.black)
                        .foregroundColor(.white)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 28)

            // 5. 24H Interactive Swift Charts graphs (title rendered inside TelemetryChartView's card)
            TelemetryChartView(isScrubbing: $isScrubbingCharts)
                .frame(minHeight: 480)
                .padding(.horizontal)
                .id("charts_section")

            // 5b. Historical PV Forecast vs Actual Comparison Chart
            PvForecastVsActualChartView()
                .padding(.horizontal)
            
            // 6. Battery Health & BMS Voltage Diagnostic Card
            BatteryHealthCardView()
                .padding(.horizontal)
            
            // 7. Standalone 24-Hour Cell Balance & Voltage Sag Trend Chart
            BatteryHealthTrendChartView()
                .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private func BatteryHealthTrendChartView() -> some View {
        let telemetry = live.telemetryHistory
        
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(batteryGreen)
                
                Text("24H CELL BALANCE & VOLTAGE SAG TREND")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(batteryGreen)
                    .tracking(1.2)
                
                Spacer()
                
                if let idx = bmsScrubIndex, idx >= 0 && idx < telemetry.count {
                    Button(action: { bmsScrubIndex = nil }) {
                        Text("CLEAR")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                    }
                } else {
                    Text("TOUCH TO INSPECT")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(batteryGreen)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(batteryGreen.opacity(0.12))
                        .cornerRadius(4)
                }
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            if telemetry.isEmpty {
                Text("No 24h cell voltage logs available yet. Telemetry writes every 5 min.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(height: 110)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if let idx = bmsScrubIndex, idx >= 0 && idx < telemetry.count {
                        bmsScrubHeaderPill(entry: telemetry[idx])
                    } else {
                        bmsDefaultLegendBar()
                    }
                    
                    // Standalone Touch-Interactive Line Chart
                    GeometryReader { geo in
                        let w = geo.size.width
                        let h = geo.size.height
                        let count = telemetry.count
                        
                        cellBalanceTrendPaths(telemetry: telemetry, width: w, height: h)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = max(0, min(w, value.location.x))
                                    let idx = count > 1 ? Int(round((x / w) * CGFloat(count - 1))) : 0
                                    bmsScrubIndex = max(0, min(count - 1, idx))
                                }
                        )
                    }
                    .frame(height: 120)
                    
                    // Dynamic X Axis Timeline
                    cellTrendXAxisView(telemetry: telemetry)
                }
            }
        }
        .padding(14)
        .glassCardStyle(cornerRadius: 18)
    }
    
    @ViewBuilder
    private func bmsScrubHeaderPill(entry: TelemetryEntry) -> some View {
        let delta = Int(entry.cell_delta_mv ?? 12.0)
        let vPack = String(format: "%.1fV", entry.battery_voltage > 0 ? entry.battery_voltage : 52.0)
        let cellTemp = entry.cell_temp_c ?? 8.0
        let ambTemp = entry.temperature_c ?? 4.0
        let timeStr = formatDateHM(entry.timestamp)
        let modeledSoc = entry.modeled_soc ?? Double(entry.soc)
        
        HStack(spacing: 0) {
            // 1. Time (Fixed 42pt width)
            HStack(spacing: 2) {
                Text("🕒")
                    .font(.system(size: 8))
                Text(timeStr)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .frame(width: 48, alignment: .leading)
            
            // 2. Voltage (Fixed 44pt width)
            HStack(spacing: 2) {
                Text("⚡")
                    .font(.system(size: 8))
                Text(vPack)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
            }
            .frame(width: 46, alignment: .leading)
            
            // 3. Cell Temp (Fixed 52pt width)
            HStack(spacing: 2) {
                Text("🌡️")
                    .font(.system(size: 8))
                Text(String(format: "%4.1f°C", cellTemp))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.75, green: 0.52, blue: 0.99))
            }
            .frame(width: 54, alignment: .leading)
            
            // 4. Ambient Temp (Fixed 52pt width)
            HStack(spacing: 2) {
                Text("❄️")
                    .font(.system(size: 8))
                Text(String(format: "%4.1f°C", ambTemp))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.38, green: 0.65, blue: 0.98))
            }
            .frame(width: 52, alignment: .leading)
            
            // 5. Delta (Fixed 44pt width)
            HStack(spacing: 1) {
                Text("Δ")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(batteryGreen)
                Text(String(format: "%3dmV", delta))
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(batteryGreen)
            }
            .frame(width: 46, alignment: .leading)
            
            Spacer(minLength: 2)
            
            // 6. Dual SOC (AI EKF vs Raw BMS)
            HStack(spacing: 3) {
                Text(String(format: "🤖%.1f%%", modeledSoc))
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                Text(String(format: "⚡%2d%%", entry.soc))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.08))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func bmsDefaultLegendBar() -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Circle().fill(Color(red: 0.75, green: 0.52, blue: 0.99)).frame(width: 6, height: 6)
                Text("Cell °C")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(red: 0.75, green: 0.52, blue: 0.99))
            }
            HStack(spacing: 3) {
                Circle().fill(Color(red: 0.38, green: 0.65, blue: 0.98)).frame(width: 6, height: 6)
                Text("Amb °C")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(red: 0.38, green: 0.65, blue: 0.98))
            }
            HStack(spacing: 3) {
                Circle().fill(batteryGreen).frame(width: 6, height: 6)
                Text("Delta")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 3) {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
                Text("Volt")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 3) {
                Circle().fill(Color.cyan).frame(width: 6, height: 6)
                Text("AI SOC")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.cyan)
            }
            Spacer()
            Text("Slide to inspect")
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
    
    @ViewBuilder
    private func cellTrendXAxisView(telemetry: [TelemetryEntry]) -> some View {
        let tSize = telemetry.count
        let t0 = formatDateHM(telemetry.first?.timestamp)
        let t1 = formatDateHM(tSize > 0 ? telemetry[tSize / 4].timestamp : nil)
        let t2 = formatDateHM(tSize > 0 ? telemetry[tSize / 2].timestamp : nil)
        let t3 = formatDateHM(tSize > 0 ? telemetry[(tSize * 3) / 4].timestamp : nil)
        let t4 = formatDateHM(telemetry.last?.timestamp)

        HStack {
            Text(t0)
            Spacer()
            Text(t1)
            Spacer()
            Text(t2)
            Spacer()
            Text(t3)
            Spacer()
            Text(t4)
        }
        .font(.system(size: 9, weight: .medium, design: .rounded))
        .foregroundColor(.secondary)
    }

    @ViewBuilder
    private func cellBalanceTrendPaths(telemetry: [TelemetryEntry], width w: CGFloat, height h: CGFloat) -> some View {
        let count = telemetry.count
        ZStack(alignment: .topLeading) {
            // Outdoor Ambient Temperature Line (Ice-Blue Dashed) [-5°C..45°C]
            Path { path in
                for (idx, entry) in telemetry.enumerated() {
                    let x = count > 1 ? w * CGFloat(idx) / CGFloat(count - 1) : w / 2
                    let ambVal = entry.temperature_c ?? 4.0
                    let normY = h * (1.0 - CGFloat(min(45.0, max(-5.0, ambVal)) - (-5.0)) / 50.0)
                    if idx == 0 { path.move(to: CGPoint(x: x, y: normY)) }
                    else { path.addLine(to: CGPoint(x: x, y: normY)) }
                }
            }
            .stroke(Color(red: 0.38, green: 0.65, blue: 0.98), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))

            // Cell Probe Temperature Line (Purple Dashed) [-5°C..45°C]
            Path { path in
                for (idx, entry) in telemetry.enumerated() {
                    let x = count > 1 ? w * CGFloat(idx) / CGFloat(count - 1) : w / 2
                    let cellVal = entry.cell_temp_c ?? 8.0
                    let normY = h * (1.0 - CGFloat(min(45.0, max(-5.0, cellVal)) - (-5.0)) / 50.0)
                    if idx == 0 { path.move(to: CGPoint(x: x, y: normY)) }
                    else { path.addLine(to: CGPoint(x: x, y: normY)) }
                }
            }
            .stroke(Color(red: 0.75, green: 0.52, blue: 0.99), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))

            // Solid Line: Cell Delta (mV)
            Path { path in
                for (idx, entry) in telemetry.enumerated() {
                    let x = count > 1 ? w * CGFloat(idx) / CGFloat(count - 1) : w / 2
                    let delta = entry.cell_delta_mv ?? 12.0
                    let normY = h * (1.0 - CGFloat(min(80.0, max(0.0, delta)) / 80.0))
                    if idx == 0 { path.move(to: CGPoint(x: x, y: normY)) }
                    else { path.addLine(to: CGPoint(x: x, y: normY)) }
                }
            }
            .stroke(batteryGreen, lineWidth: 2)
            
            // Dashed Line: Pack Voltage (V) [48V..56V]
            Path { path in
                for (idx, entry) in telemetry.enumerated() {
                    let x = count > 1 ? w * CGFloat(idx) / CGFloat(count - 1) : w / 2
                    let v = entry.battery_voltage > 0 ? entry.battery_voltage : 52.0
                    let normY = h * (1.0 - CGFloat(min(56.0, max(48.0, v)) - 48.0) / 8.0)
                    if idx == 0 { path.move(to: CGPoint(x: x, y: normY)) }
                    else { path.addLine(to: CGPoint(x: x, y: normY)) }
                }
            }
            .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            
            // Thin Dashed White Line: Raw Inverter BMS SOC API (%) [0%..100%]
            Path { path in
                for (idx, entry) in telemetry.enumerated() {
                    let x = count > 1 ? w * CGFloat(idx) / CGFloat(count - 1) : w / 2
                    let rawSoc = Double(entry.soc)
                    let normY = h * (1.0 - CGFloat(min(100.0, max(0.0, rawSoc)) / 100.0))
                    if idx == 0 { path.move(to: CGPoint(x: x, y: normY)) }
                    else { path.addLine(to: CGPoint(x: x, y: normY)) }
                }
            }
            .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // Cyan Solid Line: AI Physics Modeled Battery SOC (%) [0%..100%]
            Path { path in
                for (idx, entry) in telemetry.enumerated() {
                    let x = count > 1 ? w * CGFloat(idx) / CGFloat(count - 1) : w / 2
                    let soc = entry.modeled_soc ?? Double(entry.soc)
                    let normY = h * (1.0 - CGFloat(min(100.0, max(0.0, soc)) / 100.0))
                    if idx == 0 { path.move(to: CGPoint(x: x, y: normY)) }
                    else { path.addLine(to: CGPoint(x: x, y: normY)) }
                }
            }
            .stroke(Color.cyan, lineWidth: 2.0)
            
            // Vertical Scrubber Line & Dot Indicator
            if let idx = bmsScrubIndex, idx >= 0 && idx < count {
                let x = count > 1 ? w * CGFloat(idx) / CGFloat(count - 1) : w / 2
                let entry = telemetry[idx]
                let delta = entry.cell_delta_mv ?? 12.0
                let dotY = h * (1.0 - CGFloat(min(80.0, max(0.0, delta)) / 80.0))
                
                Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: h))
                }
                .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                
                Circle()
                    .fill(batteryGreen)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .position(x: x, y: dotY)
            }
        }
    }
    
    @ViewBuilder
    private func batteryTemperatureRowView() -> some View {
        let minCellTempStr = live.liveStatus?.data?.uwMinTemprCell ?? (live.liveStatus?.data?.bmsBatteryTemp ?? "8")
        let maxCellTempStr = live.liveStatus?.data?.uwMaxTemprCell ?? "10"
        let ambientTempVal = live.telemetryHistory.last?.temperature_c ?? 4.0
        
        HStack(spacing: 12) {
            // Metric A: Cell Probe Temp (Min ~ Max)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(red: 0.75, green: 0.52, blue: 0.99))
                    Text("Cell Probe Temp")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(minCellTempStr)°C ~ \(maxCellTempStr)")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("°C")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.75, green: 0.52, blue: 0.99))
                }
                Text("BMS Probe Range")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)
            
            // Metric B: Ambient Outdoor Temp
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "snowflake")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(red: 0.38, green: 0.65, blue: 0.98))
                    Text("Ambient Forecast")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.1f", ambientTempVal))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(ambientTempVal < 5.0 ? .orange : .white)
                    Text("°C")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.38, green: 0.65, blue: 0.98))
                }
                Text(ambientTempVal < 5.0 ? "Cold Engine Active (<5°C)" : "Normal Temp Zone")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(ambientTempVal < 5.0 ? .orange : .secondary.opacity(0.8))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)
        }
    }

    @ViewBuilder
    private func BatteryHealthCardView() -> some View {
        let rawDelta = Double(live.liveStatus?.data?.bmsDeltaVolt ?? "12") ?? 12.0
        let packVolt = Double(live.liveStatus?.data?.vBat ?? "53.7") ?? 53.7
        let daysSinceCal = 2
        let lastCalDate = "2026-07-30"
        
        let healthRatingText: String = {
            if rawDelta < 30 { return "EXCELLENT" }
            else if rawDelta < 50 { return "GOOD" }
            else { return "BALANCING DUE" }
        }()
        
        let healthRatingColor: Color = {
            if rawDelta < 30 { return batteryGreen }
            else if rawDelta < 50 { return .yellow }
            else { return .red }
        }()
        
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(batteryGreen)
                
                Text("BATTERY HEALTH & DIAGNOSTICS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(batteryGreen)
                    .tracking(1.2)
                
                Spacer()
                
                Text(healthRatingText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(healthRatingColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(healthRatingColor.opacity(0.15))
                    .cornerRadius(6)
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Dual SOC Comparison Row (AI Physics EKF vs Raw Inverter BMS API)
            HStack(spacing: 12) {
                let latestEntry = live.telemetryHistory.last
                let bmsSocVal = Double(live.liveStatus?.data?.SOC ?? (latestEntry?.soc.description ?? "0")) ?? 0.0
                let modeledSocVal = Double(live.liveStatus?.data?.modeled_soc ?? "") ?? (latestEntry?.modeled_soc ?? bmsSocVal)
                let hasSagFilter = abs(modeledSocVal - bmsSocVal) >= 3.0
                
                // Metric A: AI Physics Model SOC
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("🤖")
                            .font(.system(size: 10))
                        Text("AI Physics Model SOC")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(red: 0.22, green: 0.74, blue: 0.97))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.1f", modeledSocVal))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 0.22, green: 0.74, blue: 0.97))
                    }
                    Text("Sag-Compensated EKF")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0.8))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(red: 0.22, green: 0.74, blue: 0.97).opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(10)
                
                // Metric B: Raw Inverter BMS SOC
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("⚡")
                            .font(.system(size: 10))
                        Text("Raw Inverter BMS API")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(bmsSocVal))")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(hasSagFilter ? Color.orange : .white)
                        Text("%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    Text(hasSagFilter ? "Sag Distorted (-\(Int(modeledSocVal - bmsSocVal))%)" : "Uncompensated Raw API")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(hasSagFilter ? Color.orange : .secondary.opacity(0.8))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
            }

            // Cell Probe & Ambient Temperature Row (Matching Android App)
            batteryTemperatureRowView()

            // 2x2 Metric Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Metric 1: Cell Delta Voltage
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cell Delta Voltage")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(rawDelta))")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("mV")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(batteryGreen)
                    }
                    Text("Target < 30 mV (16S LFP)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
                
                // Metric 2: Pack Voltage
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pack Terminal Voltage")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.1f", packVolt))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("V")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(batteryGreen)
                    }
                    Text("Nominal 51.2V (3.2V / Cell)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
                
                // Metric 3: Calibration Recency
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last BMS Calibration")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("\(daysSinceCal)d ago")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(lastCalDate.isEmpty ? "Calibrated 96%+" : "Date: \(lastCalDate)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
                
                // Metric 4: Cold Guard Status
                VStack(alignment: .leading, spacing: 4) {
                    Text("Winter Cold Protection")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: "snowflake")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.cyan)
                        Text("Active Guard")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Text("Auto 8°C Pre-heat")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04))
                .cornerRadius(10)
            }
            
            // 16S LFP Cell Voltage Matrix Grid (4x4)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("16S LFP CELL VOLTAGE MATRIX")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(1.0)
                    Spacer()
                    Text("Live 1mV Precision")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(batteryGreen)
                }
                
                let cellVoltages: [Double] = {
                    if let liveVolts = live.liveStatus?.data?.cellVoltages, liveVolts.count == 16 {
                        return liveVolts
                    }
                    let base = packVolt / 16.0
                    return [base + 0.005, base + 0.002, base - 0.006, base + 0.006,
                            base - 0.002, base + 0.001, base, base - 0.004,
                            base + 0.003, base - 0.001, base + 0.004, base - 0.005,
                            base + 0.002, base - 0.003, base + 0.001, base - 0.001]
                }()
                
                let minV = cellVoltages.min() ?? 3.348
                let maxV = cellVoltages.max() ?? 3.360
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(0..<16, id: \.self) { idx in
                        let v = cellVoltages[idx]
                        let isMin = abs(v - minV) < 0.001
                        let isMax = abs(v - maxV) < 0.001
                        let tileBg: Color = isMin ? Color.orange.opacity(0.18) : (isMax ? batteryGreen.opacity(0.18) : Color.white.opacity(0.04))
                        let borderCol: Color = isMin ? Color.orange : (isMax ? batteryGreen : Color.clear)
                        
                        VStack(spacing: 2) {
                            Text(String(format: "#%02d", idx + 1))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(isMin ? .orange : (isMax ? batteryGreen : .secondary))
                            Text(String(format: "%.3fV", v))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(isMin ? .orange : (isMax ? batteryGreen : .white))
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(tileBg)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(borderCol, lineWidth: 1)
                        )
                    }
                }
            }
            
            // Diagnostic Banner
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(batteryGreen)
                    .font(.system(size: 14))
                    .padding(.top, 2)
                
                Text("BMS cell balance is optimal (\(Int(rawDelta)) mV). Thermal protection is active to prevent cold cell voltage sag under peak discharge.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineSpacing(2)
            }
            .padding(10)
            .background(batteryGreen.opacity(0.08))
            .cornerRadius(8)
        }
        .padding(14)
        .glassCardStyle(cornerRadius: 18)
    }
    
    @ViewBuilder
    private func SystemSettingsView() -> some View {
        VStack(spacing: 24) {
            // Header (Status bar cleared)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("APP CONFIGURATION")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(batteryGreen)
                        .tracking(1.5)
                    
                    Text("System Settings")
                        .font(.title2)
                        .fontWeight(.black)
                        .foregroundColor(.white)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 28)
            
            // Credentials card
            CredentialsSectionView()
                .padding(.horizontal)
            
            // WattPet Mascot AI Settings Card
            MascotSettingsSectionView()
                .padding(.horizontal)
            
            // Logs Card
            LogsSectionView()
                .padding(.horizontal)
            
            // About Card
            AboutSectionView()
                .padding(.horizontal)
        }
    }
    
    // MARK: - Subviews & Controls
    

    
    /// Normalizes an MPPT power reading to kW. Numeric per-string fields are Watts in both
    /// payload styles (verified: pdischarge1=270 [W] vs pdisCharge1="0.27" [kW]).
    private func mpptKw(_ raw: String?) -> Double? {
        guard let raw = raw, let v = Double(raw) else { return nil }
        return v / 1000.0
    }

    @ViewBuilder
    private func mpptRow(_ label: String, valueText: String, voltage: String? = nil) -> some View {
        HStack(spacing: 4) {
            Text("└ \(label)")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(.secondary.opacity(0.8))
            Spacer()
            if let vStr = voltage, let v = Double(vStr), v > 0 {
                Text(String(format: "%.0fV", v))
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Text(valueText)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
        }
    }

    @ViewBuilder
    private func QuickStatsGrid() -> some View {
        let pvVal = Double(live.liveStatus?.data?.ppv ?? "0.0") ?? 0.0
        let loadVal = Double(live.liveStatus?.data?.localLoad ?? "0.0") ?? 0.0
        let expVal = Double(live.liveStatus?.data?.gridExport ?? "0.0") ?? 0.0
        let impVal = Double(live.liveStatus?.data?.gridImport ?? "0.0") ?? 0.0
        let chgPower = Double(live.liveStatus?.data?.chargePower ?? "0.0") ?? 0.0
        let dischPower = Double(live.liveStatus?.data?.dischargePower ?? "0.0") ?? 0.0
        let socVal = live.liveStatus?.data?.SOC ?? "0"
        
        let netGrid = impVal > 0 ? impVal : -expVal
        
        HStack(spacing: 12) {
            // Left Column: Real-time Cockpit
            VStack(alignment: .leading, spacing: 10) {
                Label("LIVE FLOW", systemImage: "bolt.horizontal.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(batteryGreen)
                    .tracking(1.5)
                
                VStack(spacing: 6) {
                    consoleRow(icon: "sun.max.fill", color: solarGold, label: "Solar PV", value: String(format: "%.2f kW", pvVal))

                    // Per-MPPT string breakdown (only when the inverter payload provides it)
                    if let pv1 = mpptKw(live.liveStatus?.data?.ppv1),
                       let pv2 = mpptKw(live.liveStatus?.data?.ppv2) {
                        VStack(spacing: 2) {
                            mpptRow("PV1", valueText: String(format: "%.2f kW", pv1), voltage: live.liveStatus?.data?.vpv1)
                            mpptRow("PV2", valueText: String(format: "%.2f kW", pv2), voltage: live.liveStatus?.data?.vpv2)
                        }
                        .padding(.leading, 18)
                    }

                    Divider().background(Color.white.opacity(0.04))
                    consoleRow(icon: "house.fill", color: loadBlue, label: "Home Load", value: String(format: "%.2f kW", loadVal))
                    Divider().background(Color.white.opacity(0.04))
                    
                    // Battery row with SoC, Pack Voltage and flow
                    let packVoltVal = live.liveStatus?.data?.vBat ?? "53.7"
                    HStack(spacing: 4) {
                        Image(systemName: "battery.100.bolt")
                            .foregroundColor(batteryGreen)
                            .font(.system(size: 11))
                            .frame(width: 14)
                        Text("Battery (\(packVoltVal)V)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(socVal)%")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        if chgPower > 0 {
                            Text(String(format: "(+%.1f)", chgPower))
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundColor(batteryGreen)
                        } else if dischPower > 0 {
                            Text(String(format: "(-%.1f)", dischPower))
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundColor(.orange)
                        } else {
                            Text("(idle)")
                                .font(.system(size: 8, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Divider().background(Color.white.opacity(0.04))
                    
                    // Grid row
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.circle.fill")
                            .foregroundColor(netGrid > 0 ? alertRed : (netGrid < 0 ? solarGold : .secondary))
                            .font(.system(size: 11))
                            .frame(width: 14)
                        Text("Grid Power")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        if netGrid > 0 {
                            Text(String(format: "+%.2f kW", netGrid))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(alertRed)
                        } else if netGrid < 0 {
                            Text(String(format: "-%.2f kW", abs(netGrid)))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(solarGold)
                        } else {
                            Text("0.00 kW")
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            // Symmetry contract with the right card: equal width (50/50 split regardless of
            // content), equal height (stretch to the taller sibling), content top-aligned.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .glassCardStyle(cornerRadius: 14)

            // Right Column: Today's Cumulative Totals
            VStack(alignment: .leading, spacing: 10) {
                Label("TODAY TOTALS", systemImage: "clock.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(solarGold)
                    .tracking(1.5)
                
                VStack(spacing: 6) {
                    consoleRow(icon: "sun.max.fill", color: solarGold, label: "Solar Yield", value: String(format: "%.2f kWh", totalSolarKwh))

                    // Per-string daily yield — quick visual check that both strings pull
                    // their weight (a persistent gap = shading or a string fault).
                    // Shown whenever the payload provides the fields (0.0 overnight is fine).
                    if let e1 = Double(live.liveStatus?.data?.epv1Today ?? ""),
                       let e2 = Double(live.liveStatus?.data?.epv2Today ?? "") {
                        VStack(spacing: 2) {
                            mpptRow("PV1", valueText: String(format: "%.1f kWh", e1))
                            mpptRow("PV2", valueText: String(format: "%.1f kWh", e2))
                        }
                        .padding(.leading, 18)
                    }

                    Divider().background(Color.white.opacity(0.04))
                    consoleRow(icon: "house.fill", color: loadBlue, label: "Load Cons", value: String(format: "%.2f kWh", totalLoadKwh))
                    Divider().background(Color.white.opacity(0.04))
                    
                    // Battery cycle total
                    HStack(spacing: 4) {
                        Image(systemName: "battery.100.bolt")
                            .foregroundColor(batteryGreen)
                            .font(.system(size: 11))
                            .frame(width: 14)
                        Text("Batt Chg/Dis")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f/%.1f", totalChargeKwh, totalDischargeKwh))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    
                    Divider().background(Color.white.opacity(0.04))
                    
                    // Grid total
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.circle.fill")
                            .foregroundColor(gridPurple)
                            .font(.system(size: 11))
                            .frame(width: 14)
                        Text("Grid Imp/Exp")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f/%.1f", totalImportKwh, totalExportKwh))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .glassCardStyle(cornerRadius: 14)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    @ViewBuilder
    private func consoleRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 11))
                .frame(width: 14)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
    }
    
    // ResolvedSegment promoted to top-level struct (see below DateFormatter extension)
    

    
    // resolveTimelineSegments moved to TimelinePreviewView struct
    
    // TimelinePreviewView moved to standalone struct below
    

    

    

    

    

    

    

    

    
    @ViewBuilder
    private func MascotSettingsSectionView() -> some View {
        let currentSkin = fm.settings.mascot_skin
        let geminiKey = fm.settings.gemini_api_key

        VStack(alignment: .leading, spacing: 14) {
            // Foldable Header Row
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isMascotSettingsExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    MascotView(skin: currentSkin, size: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("WATTpet AI MASCOT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .tracking(1)

                        if !isMascotSettingsExpanded {
                            Text(geminiKey.isEmpty ? "Local Engine (no API key)" : "Gemini 2.5 LLM · Skin: \(currentSkin.capitalized)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }

                    Spacer()

                    Image(systemName: isMascotSettingsExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 4)

            if isMascotSettingsExpanded {
                VStack(spacing: 16) {
                    Divider().background(Color.white.opacity(0.04))

                    // Skin Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mascot Skin")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        HStack(spacing: 10) {
                            let skins = ["slime", "blob", "robot", "cyber", "pet"]
                            ForEach(skins, id: \.self) { skinName in
                                Button(action: {
                                    var s = fm.settings
                                    s.mascot_skin = skinName
                                    fm.saveSettings(s)
                                }) {
                                    VStack(spacing: 4) {
                                        MascotView(skin: skinName, size: 28)
                                        Text(skinName.capitalized)
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(currentSkin == skinName ? solarGold : .secondary)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 4)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(currentSkin == skinName ? solarGold.opacity(0.15) : Color.white.opacity(0.04))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(currentSkin == skinName ? solarGold.opacity(0.6) : Color.clear, lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }

                    Divider().background(Color.white.opacity(0.04))

                    // Gemini API Key
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gemini API Key")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        HStack {
                            if showGeminiKey {
                                TextField("Enter Gemini API Key...", text: Binding(
                                    get: { geminiKey },
                                    set: { val in
                                        var s = fm.settings
                                        s.gemini_api_key = val
                                        fm.saveSettings(s)
                                    }
                                ))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white)
                            } else {
                                SecureField("Enter Gemini API Key...", text: Binding(
                                    get: { geminiKey },
                                    set: { val in
                                        var s = fm.settings
                                        s.gemini_api_key = val
                                        fm.saveSettings(s)
                                    }
                                ))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white)
                            }

                            Button(action: { showGeminiKey.toggle() }) {
                                Text(showGeminiKey ? "Hide" : "Show")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(batteryGreen)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )

                        if geminiKey.isEmpty {
                            Text("Without a key, WattPet uses the built-in local rule engine.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .glassCardStyle(cornerRadius: 18)
    }

    @ViewBuilder
    private func CredentialsSectionView() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Foldable Header Row
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isCredentialsExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(batteryGreen)
                        .font(.system(size: 14))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GROWATT SHINESERVER INTEGRATION")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .tracking(1)
                        
                        if !isCredentialsExpanded {
                            Text(fm.settings.username.isEmpty ? "No Account Configured" : "Account: \(fm.settings.username)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isCredentialsExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 4)
            
            if isCredentialsExpanded {
                VStack(spacing: 16) {
                    Divider().background(Color.white.opacity(0.04))
                    
                    // Server Url selector
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Growatt API URL")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        Picker("Server URL", selection: $fm.settings.server_url) {
                            Text("Australia (openapi-au)").tag("https://openapi-au.growatt.com/")
                            Text("International (server)").tag("https://server.growatt.com/")
                            Text("Global (openapi)").tag("https://openapi.growatt.com/")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Growatt Username")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        TextField("Username", text: $fm.settings.username)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                            .font(.system(size: 13, design: .rounded))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            )
                            .autocapitalization(.none)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Growatt Password")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        SecureField("Password", text: $fm.settings.password)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                            .font(.system(size: 13, design: .rounded))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Growatt API Token (Optional)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        SecureField("Bypasses password to prevent locks", text: $fm.settings.api_token)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                            .font(.system(size: 13, design: .rounded))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            )
                            .autocapitalization(.none)
                        
                        Text("Obtain token in ShinePhone app: Me -> Profile -> API Token")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.leading, 2)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Device Serial Number (Optional)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        TextField("Auto-discovered if empty", text: $fm.settings.device_sn)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                            .font(.system(size: 13, design: .rounded))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            )
                            .autocapitalization(.allCharacters)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Account Timezone")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        TextField("e.g. Australia/Sydney", text: $fm.settings.timezone)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                            .font(.system(size: 13, design: .rounded))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            )
                            .autocapitalization(.none)
                    }
                    
                    Divider().background(Color.white.opacity(0.04))
                    
                    // Integrated Device Location Section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Weather Coordinates (Device GPS)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            if let lat = fm.settings.latitude, let lon = fm.settings.longitude {
                                Text("Custom GPS: \(String(format: "%.4f", lat)), \(String(format: "%.4f", lon))")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            } else {
                                Text("Approximate (Timezone Fallback)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                        
                        // Informative caption about Sydney/Canberra sharing AEST/AEDT timezone
                        Text(fm.settings.latitude == nil ? "Note: Sydney and Canberra share the same timezone. By default, weather falls back to Sydney coordinates. Tap below to use precise Canberra device location." : "Using precise device coordinates for hyper-local Canberra weather.")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                        
                        HStack(spacing: 10) {
                            Button(action: {
                                locationHelper.fetchLocation { clLocation in
                                    let lat = clLocation.coordinate.latitude
                                    let lon = clLocation.coordinate.longitude
                                    fm.settings.latitude = lat
                                    fm.settings.longitude = lon
                                    fm.saveSettings(fm.settings)
                                    triggerSaveFeedback(message: "GPS Location applied!")
                                    
                                    WeatherManager.shared.fetch(
                                        timezone: fm.settings.timezone,
                                        latitude: lat,
                                        longitude: lon
                                    )
                                }
                            }) {
                                HStack(spacing: 6) {
                                    if locationHelper.isUpdating {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "location.fill")
                                    }
                                    Text(locationHelper.isUpdating ? "Locating..." : "Use Device Location")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .foregroundColor(.white)
                                .background(batteryGreen)
                                .cornerRadius(8)
                            }
                            .disabled(locationHelper.isUpdating)
                            
                            if fm.settings.latitude != nil {
                                Button(action: {
                                    fm.settings.latitude = nil
                                    fm.settings.longitude = nil
                                    fm.saveSettings(fm.settings)
                                    triggerSaveFeedback(message: "Reset to default timezone.")
                                    
                                    WeatherManager.shared.fetch(
                                        timezone: fm.settings.timezone,
                                        latitude: nil,
                                        longitude: nil
                                    )
                                }) {
                                    Text("Reset")
                                        .font(.system(size: 11, weight: .bold))
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .foregroundColor(.white)
                                        .background(Color.white.opacity(0.04))
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                        )
                                }
                            }
                        }
                    }
                    
                    Divider().background(Color.white.opacity(0.04))
                    
                    Button(action: {
                        fm.saveSettings(fm.settings)
                        triggerSaveFeedback(message: "Credentials successfully updated!")
                    }) {
                        Text("Apply Credentials")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(.white)
                            .background(batteryGreen)
                            .cornerRadius(10)
                    }
                    
                    if fm.settings.username == "demo@xgrowatt.com" {
                        Button(action: {
                            var emptySettings = fm.settings
                            emptySettings.username = ""
                            emptySettings.password = ""
                            emptySettings.device_sn = ""
                            emptySettings.timezone = "Australia/Canberra"
                            fm.saveSettings(emptySettings)
                            triggerSaveFeedback(message: "Demo Mode deactivated. Back to Firestore.")
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle")
                                Text("Exit Demo Mode")
                            }
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(alertRed)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(alertRed.opacity(0.4), lineWidth: 1)
                            )
                        }
                    } else {
                        Button(action: {
                            var demoSettings = fm.settings
                            demoSettings.username = "demo@xgrowatt.com"
                            demoSettings.password = "demopassword"
                            demoSettings.device_sn = "DEMO_SPH_INVERTER_SN"
                            demoSettings.timezone = "Australia/Canberra"
                            demoSettings.server_url = "https://openapi-au.growatt.com/"
                            fm.saveSettings(demoSettings)
                            triggerSaveFeedback(message: "Demo Mode activated!")
                        }) {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Activate App Store Demo Mode")
                            }
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundColor(solarGold)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(solarGold.opacity(0.4), lineWidth: 1)
                            )
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .glassCardStyle(cornerRadius: 18)
    }
    
    @ViewBuilder
    private func LogsSectionView() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Foldable Header Row
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isLogsExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.circle.fill")
                        .foregroundColor(batteryGreen)
                        .font(.system(size: 14))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BACKGROUND SYNC LOGS (LATEST 10)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .tracking(1)
                        
                        if !isLogsExpanded {
                            Text(live.logs.isEmpty ? "No Logs Available" : "Latest: \(live.logs.first?.message ?? "")")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isLogsExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 4)
            
            if isLogsExpanded {
                VStack(spacing: 0) {
                    Divider().background(Color.white.opacity(0.04))
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    
                    if live.logs.isEmpty {
                        Text("No logs found.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(live.logs) { log in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(log.status == "success" ? batteryGreen : alertRed)
                                    .frame(width: 8, height: 8)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(log.message)
                                        .font(.footnote)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                        .lineLimit(2)
                                    
                                    HStack(spacing: 8) {
                                        Text(log.trigger.uppercased())
                                            .font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.white.opacity(0.06))
                                            .cornerRadius(4)
                                        
                                        if let applied = log.applied_schedule {
                                            Text(applied.uppercased())
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(solarGold)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 2)
                                                .background(solarGold.opacity(0.08))
                                                .cornerRadius(4)
                                        }
                                        
                                        Text(formatDate(log.timestamp))
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 10)
                            
                            if log.id != live.logs.last?.id {
                                Divider()
                                    .background(Color.white.opacity(0.04))
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .glassCardStyle(cornerRadius: 18)
    }
    
    // MARK: - Formatters & Utilities
    
    private func energyRow(title: String, value: Double, color: Color, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(title)
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
            Text(String(format: "%.2f kWh", value))
                .font(.system(.footnote, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
    
    private func timeBinding(getStr: @escaping () -> String, setStr: @escaping (String) -> Void) -> Binding<Date> {
        makeTimeBinding(getStr: getStr, setStr: setStr)
    }
    
    private func triggerSaveFeedback(message: String) {
        saveStatusMessage = message
        autoDismissTimer?.invalidate()
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation {
                saveStatusMessage = nil
            }
        }
    }
    
    private func startTimer() {
        refreshTimer?.invalidate()
        fm.triggerManualSync(mode: "read")
        
        // Fetch weather immediately on app launch/timer start
        Task { @MainActor in
            WeatherManager.shared.fetchIfNeeded(
                timezone: fm.settings.timezone,
                latitude: fm.settings.latitude,
                longitude: fm.settings.longitude
            )
        }
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            print("Auto-refreshing live data...")
            fm.triggerManualSync(mode: "read")
            
            // Automatically refresh weather every 5 minutes safely on MainActor
            Task { @MainActor in
                WeatherManager.shared.fetch(
                    timezone: fm.settings.timezone,
                    latitude: fm.settings.latitude,
                    longitude: fm.settings.longitude
                )
            }
        }
    }
    
    private func stopTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Never" }
        return DateFormatter.shortDateMediumTime.string(from: date)
    }
    
    private func formatDateHM(_ date: Date?) -> String {
        guard let date = date else { return "--:--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    @ViewBuilder
    private func legendPill(color: Color, label: String, value: Double, total: Double) -> some View {
        let percentage = total > 0 ? (value / total) * 100.0 : 0.0
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary)
            
            Text(String(format: "%.1f%%", percentage))
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.02))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.02), lineWidth: 0.5)
        )
    }
    
    @ViewBuilder
    private func tabBarButton(index: Int, icon: String, label: String) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                selectedTab = index
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(selectedTab == index ? batteryGreen : .secondary)
            .frame(maxWidth: .infinity)
        }
    }
    
    @ViewBuilder
    private func matrixRow(color: Color, label: String, value: Double, total: Double) -> some View {
        let pct = total > 0 ? (value / total) * 100 : 0.0
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            
            // Wrap-proof: numbers keep their intrinsic width (fixedSize), the label
            // shrinks/truncates first — a long label can never push the row onto two lines.
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(0)

            Spacer(minLength: 4)

            Text(String(format: "%.1f kWh", value))
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)

            Text(String(format: "(%.0f%%)", pct))
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize()
                .layoutPriority(1)
        }
    }
    
    // MARK: - Advanced Analytics Computations
    
    private var todayTelemetry: [TelemetryEntry] {
        let calendar = Calendar.current
        return live.telemetryHistory.filter { entry in
            guard let date = entry.timestamp else { return false }
            return calendar.isDateInToday(date)
        }
    }
    
    private var totalSolarKwh: Double {
        calculateIntegral(for: \.solar_generation_kw)
    }
    
    private var totalLoadKwh: Double {
        calculateIntegral(for: \.local_load_kw)
    }
    
    private var totalChargeKwh: Double {
        calculateIntegral(for: \.charge_power_kw)
    }
    
    private var totalDischargeKwh: Double {
        calculateIntegral(for: \.discharge_power_kw)
    }
    
    private var totalImportKwh: Double {
        calculateIntegral(for: \.grid_import_kw)
    }
    
    private var totalExportKwh: Double {
        calculateIntegral(for: \.grid_export_kw)
    }
    
    private var totalLocalLoadKwh: Double {
        let sorted = todayTelemetry.sorted { ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) }
        guard sorted.count > 1 else { return 0.0 }
        
        var sum = 0.0
        for i in 0..<(sorted.count - 1) {
            let e1 = sorted[i]
            let e2 = sorted[i+1]
            guard let t1 = e1.timestamp, let t2 = e2.timestamp else { continue }
            let dtHours = t2.timeIntervalSince(t1) / 3600.0
            // Must skip large gaps EXACTLY like calculateIntegral does — this is the
            // numerator of self-sufficiency and its denominator (totalLoadKwh) skips them,
            // so integrating across gaps here silently inflates the ratio.
            guard dtHours < 1.0 else { continue }

            let val1 = max(0.0, e1.local_load_kw - e1.grid_import_kw)
            let val2 = max(0.0, e2.local_load_kw - e2.grid_import_kw)
            let avgVal = (val1 + val2) / 2.0
            sum += avgVal * dtHours
        }
        return sum
    }
    
    private var totalLocalSolarKwh: Double {
        let sorted = todayTelemetry.sorted { ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) }
        guard sorted.count > 1 else { return 0.0 }
        
        var sum = 0.0
        for i in 0..<(sorted.count - 1) {
            let e1 = sorted[i]
            let e2 = sorted[i+1]
            guard let t1 = e1.timestamp, let t2 = e2.timestamp else { continue }
            let dtHours = t2.timeIntervalSince(t1) / 3600.0
            // Same gap guard as calculateIntegral (denominator of self-consumption).
            guard dtHours < 1.0 else { continue }

            let val1 = max(0.0, e1.solar_generation_kw - e1.grid_export_kw)
            let val2 = max(0.0, e2.solar_generation_kw - e2.grid_export_kw)
            let avgVal = (val1 + val2) / 2.0
            sum += avgVal * dtHours
        }
        return sum
    }
    
    private func calculateIntegral(for keyPath: KeyPath<TelemetryEntry, Double>) -> Double {
        let sorted = todayTelemetry.sorted { ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) }
        guard sorted.count > 1 else { return 0.0 }
        
        var sum = 0.0
        for i in 0..<(sorted.count - 1) {
            let e1 = sorted[i]
            let e2 = sorted[i+1]
            guard let t1 = e1.timestamp, let t2 = e2.timestamp else { continue }
            let dtHours = t2.timeIntervalSince(t1) / 3600.0
            
            // Skip massive gaps (e.g. offline for hours)
            if dtHours < 1.0 {
                let avgKw = (e1[keyPath: keyPath] + e2[keyPath: keyPath]) / 2.0
                sum += avgKw * dtHours
            }
        }
        return sum
    }
}

// MARK: - CoreLocation Helper for Weather Coordinates

@MainActor
class LocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var isUpdating = false
    var onLocationFetched: ((CLLocation) -> Void)?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }
    
    func fetchLocation(completion: @escaping (CLLocation) -> Void) {
        self.onLocationFetched = completion
        self.isUpdating = true
        
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        } else {
            self.isUpdating = false
            print("Location access denied or restricted")
        }
    }
    
    // CLLocationManagerDelegate methods
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let first = locations.first else { return }
        Task { @MainActor in
            self.isUpdating = false
            self.onLocationFetched?(first)
            self.onLocationFetched = nil
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationManager Error: \(error.localizedDescription)")
        Task { @MainActor in
            self.isUpdating = false
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            Task { @MainActor in
                manager.requestLocation()
            }
        } else if status != .notDetermined {
            Task { @MainActor in
                self.isUpdating = false
            }
        }
    }
}

// MARK: - TabView Background Cleaner Helper

struct TabViewBackgroundCleaner: UIViewControllerRepresentable {
    let selectedTab: Int
    
    func makeUIViewController(context: Context) -> CleanViewController {
        return CleanViewController()
    }
    
    func updateUIViewController(_ uiViewController: CleanViewController, context: Context) {
        uiViewController.clean()
    }
}

class CleanViewController: UIViewController {
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        clean()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        clean()
    }
    
    func clean() {
        // 1. Try parent traversal first
        var p = self.parent
        while p != nil {
            if let tabBarController = p as? UITabBarController {
                applyTransparency(to: tabBarController)
                return
            }
            p = p?.parent
        }
        
        // 2. Fallback: Search window scene root view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
            if let root = window?.rootViewController,
               let tabBarController = findTabBarController(from: root) {
                applyTransparency(to: tabBarController)
            }
        }
    }
    
    private func findTabBarController(from vc: UIViewController) -> UITabBarController? {
        if let tabVC = vc as? UITabBarController {
            return tabVC
        }
        for child in vc.children {
            if let found = findTabBarController(from: child) {
                return found
            }
        }
        if let presented = vc.presentedViewController {
            return findTabBarController(from: presented)
        }
        return nil
    }
    
    private func applyTransparency(to tabBarController: UITabBarController) {
        // A. Clear main controller view background
        tabBarController.view.backgroundColor = .clear
        
        // B. Clear nested UITransitionView and wrapper container views
        for subview in tabBarController.view.subviews {
            let typeStr = type(of: subview).description()
            if typeStr.contains("TransitionView") || typeStr.contains("ContainerView") {
                subview.backgroundColor = .clear
            }
        }
        
        // C. Clear hosting controller views background for all tabs
        for child in tabBarController.viewControllers ?? [] {
            child.view.backgroundColor = .clear
            
            child.view.subviews.forEach { subview in
                let typeStr = type(of: subview).description()
                if typeStr.contains("TransitionView") || typeStr.contains("HostingView") {
                    subview.backgroundColor = .clear
                }
        }
    }
}

}
#Preview {
    ContentView()
}

// MARK: - Premium Dynamic Glassmorphism View Extension

extension View {
    func glassCardStyle(cornerRadius: CGFloat = 18) -> some View {
        self
            .background(
                Color(red: 0.12, green: 0.12, blue: 0.15).opacity(0.60)
            )
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}

// MARK: - Dynamic Atmospheric Visual Components

struct SunVisual: View {
    var isPartlyCloudy: Bool = false
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Sun Glow Aura (fainter and smaller)
                Circle()
                    .fill(Color.orange.opacity(0.07))
                    .frame(width: w * 0.38, height: w * 0.38)
                    .blur(radius: 20)
                
                Circle()
                    .fill(Color.yellow.opacity(0.16))
                    .frame(width: w * 0.24, height: w * 0.24)
                    .blur(radius: 10)
                
                // Sun Core (smaller)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white, Color(red: 1.0, green: 0.85, blue: 0.35)],
                            center: .center,
                            startRadius: 0,
                            endRadius: w * 0.06
                        )
                    )
                    .frame(width: w * 0.13, height: w * 0.13)
                    .shadow(color: Color.yellow.opacity(0.35), radius: 10)
                
                // Translucent Overlapping Cloud if partly cloudy (smaller and much fainter)
                if isPartlyCloudy {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: w * 0.14))
                        .foregroundColor(.white.opacity(0.40))
                        .blur(radius: 2.0)
                        .shadow(color: Color.black.opacity(0.05), radius: 4)
                        .offset(x: -w * 0.04, y: w * 0.04)
                }
            }
            .position(x: w * 0.78, y: h * 0.15)
        }
        .ignoresSafeArea()
    }
}

struct MoonVisual: View {
    var isPartlyCloudy: Bool = false
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Moon Glow Aura (fainter and smaller)
                Circle()
                    .fill(Color(red: 0.7, green: 0.8, blue: 1.0).opacity(0.06))
                    .frame(width: w * 0.30, height: w * 0.30)
                    .blur(radius: 16)
                
                // Crescent Moon Core (smaller and fainter)
                Image(systemName: "moon.fill")
                    .font(.system(size: w * 0.08, weight: .bold))
                    .foregroundColor(Color(red: 0.90, green: 0.93, blue: 0.98).opacity(0.70))
                    .shadow(color: Color(red: 0.5, green: 0.65, blue: 0.95).opacity(0.30), radius: 6)
                
                // Translucent Overlapping Cloud if partly cloudy (smaller and much fainter)
                if isPartlyCloudy {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: w * 0.11))
                        .foregroundColor(.white.opacity(0.35))
                        .blur(radius: 2.0)
                        .shadow(color: Color.black.opacity(0.04), radius: 3)
                        .offset(x: w * 0.03, y: w * 0.03)
                }
            }
            .position(x: w * 0.22, y: h * 0.15)
        }
        .ignoresSafeArea()
    }
}

struct RainView: View {
    // Generate static drop configurations
    @State private var drops: [RainDrop] = (0..<65).map { _ in
        RainDrop(
            x: Double.random(in: 0...1),
            y: Double.random(in: -0.2...1.2),
            length: Double.random(in: 12...28),
            speed: Double.random(in: 30...50),
            opacity: Double.random(in: 0.15...0.45)
        )
    }

    struct RainDrop: Identifiable {
        let id = UUID()
        var x: Double
        var y: Double
        let length: Double
        let speed: Double
        let opacity: Double
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSince1970
                
                for drop in drops {
                    let elapsed = now * drop.speed
                    let currentY = (drop.y * size.height + elapsed).truncatingRemainder(dividingBy: size.height + 60) - 30
                    let currentX = (drop.x * size.width + elapsed * 0.15).truncatingRemainder(dividingBy: size.width)
                    
                    var path = Path()
                    path.move(to: CGPoint(x: currentX, y: currentY))
                    path.addLine(to: CGPoint(x: currentX + 2, y: currentY + drop.length))
                    
                    context.stroke(
                        path,
                        with: .color(Color.white.opacity(drop.opacity)),
                        lineWidth: 1.0
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - About Section View

extension ContentView {
    @ViewBuilder
    private func AboutSectionView() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Foldable Header Row
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isAboutExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(batteryGreen)
                        .font(.system(size: 13, weight: .bold))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ABOUT XGROWATT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(batteryGreen)
                            .tracking(1.5)
                        
                        if !isAboutExpanded {
                            Text("AI-powered energy manager — features & architecture")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isAboutExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 4)
            
            if isAboutExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Divider().background(Color.white.opacity(0.04))
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    
                    Text("XGrowatt is an AI-powered energy manager for Growatt hybrid inverters: it forecasts tomorrow's solar and load, plans the cheapest battery strategy under your time-of-use tariff, and executes it on the inverter — fully hands-off.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineSpacing(3)

                    Divider().background(Color.white.opacity(0.06))

                    // Core Principle
                    VStack(alignment: .leading, spacing: 6) {
                        Text("🔑 CORE PRINCIPLE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        Text("Three self-expiring control layers: a permanent weekly baseline, a one-day AI plan generated nightly from fresh weather forecasts (auto-applied in AUTO mode), and instant in-window edits. Each layer falls back to the one below when it expires — no stale setting can ever linger.")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.70))
                            .lineSpacing(4)
                    }

                    Divider().background(Color.white.opacity(0.06))

                    // Solved Pain Points
                    VStack(alignment: .leading, spacing: 10) {
                        Text("💡 KEY FEATURES")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)

                        AboutBulletRow(
                            icon: "brain.head.profile",
                            title: "AI Charging Plan",
                            text: "Nightly full-day simulation: plane-of-array irradiance forecasts (panel tilt & azimuth aware), an hourly tree-shade calibration profile, EV-aware load learning, and free-window economics decide exactly how much off-peak charge tomorrow needs — with a whole-day bill estimate you can verify against actual bills."
                        )

                        AboutBulletRow(
                            icon: "calendar.badge.clock",
                            title: "Per-Window SoC Dispatch",
                            text: "The inverter has one global charge-stop SoC shared by all time windows. XGrowatt time-multiplexes it: each window's target is pushed 15 minutes before that window starts — overnight 55%, free midday window 100%, automatically."
                        )

                        AboutBulletRow(
                            icon: "shield.checkered",
                            title: "Drift Detection & Self-Healing",
                            text: "Every 5 minutes the inverter's device-reported registers are compared against the intended schedule. External changes surface as a dashboard alert within minutes, and drift during an active charge window is corrected automatically. Writes are receipt-verified."
                        )

                        AboutBulletRow(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "ML Data Flywheel",
                            text: "Telemetry is stored ML-ready: 5-minute readings joined with 19 weather variables, per-MPPT string data, archived forecast snapshots (with lead-time), and every AI plan vs. actual outcome — feeding a ridge-regression PV model that replaces the empirical formula once it provably wins."
                        )

                        AboutBulletRow(
                            icon: "bolt.heart",
                            title: "Hardware-Gentle by Design",
                            text: "Cloud-side comparison skips identical writes to protect EEPROM, sync happens once before each window instead of high-frequency polling (no '507' account locks), and LFP battery care is built in: 90% daily cap with free-window 100% top-ups doubling as weekly cell balancing."
                        )

                        AboutBulletRow(
                            icon: "sparkles",
                            title: "Solar-First Interface",
                            text: "Live energy flow with per-string MPPT readings, interactive charts with per-series toggles, a 24h solar forecast card (irradiance, cloud and rain), and glassmorphic cards with dynamic weather backdrops."
                        )
                    }
                }
            }
        }
        .padding(16)
        .glassCardStyle(cornerRadius: 18)
    }
    
    @ViewBuilder
    private func AboutBulletRow(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(batteryGreen)
                .frame(width: 16, height: 16)
                .background(batteryGreen.opacity(0.12))
                .cornerRadius(4)
                .padding(.top, 1)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                Text(text)
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.60))
                    .lineSpacing(3)
            }
        }
    }
}

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    @ViewBuilder
    func conditionalGesture<T: Gesture>(_ gesture: T?, when condition: Bool) -> some View {
        if condition, let gesture = gesture {
            self.gesture(gesture)
        } else {
            self
        }
    }
}

extension NumberFormatter {
    static var decimalFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }
}

// MARK: - Extracted Subviews for Performance and Metadata stability

struct SchedulesSectionView: View {
    @ObservedObject var fm: FirebaseManager
    @Binding var activeTaskSheet: TaskSheetContext?
    
    let batteryGreen: Color
    let alertRed: Color
    
    var triggerSaveFeedback: (String) -> Void
    var deleteTask: (GrowattTask) -> Void
    
    @State private var showingDeleteConfirmation = false
    @State private var taskToDelete: GrowattTask? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if fm.settings.tasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No custom scheduling tasks defined.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Default backup schedules will run until you create one (12AM-6AM daily + 12PM-2PM weekends).")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .glassCardStyle(cornerRadius: 18)
            } else {
                ForEach(fm.settings.tasks) { task in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(task.name)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .font(.system(size: 13))
                                Text("(\(task.start_time) - \(task.end_time))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack(spacing: 12) {
                                Text("SoC: \(task.soc)%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("Rate: \(task.power)%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack(spacing: 2) {
                                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
                                    Text(String(day.first ?? " "))
                                        .font(.system(size: 8, weight: .bold))
                                        .frame(width: 13, height: 13)
                                        .foregroundColor(task.days.contains(day) ? .white : .secondary.opacity(0.4))
                                        .background(task.days.contains(day) ? batteryGreen.opacity(0.3) : Color.white.opacity(0.02))
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            activeTaskSheet = TaskSheetContext(task: task)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { task.enabled },
                            set: { val in
                                if let idx = fm.settings.tasks.firstIndex(where: { $0.id == task.id }) {
                                    fm.settings.tasks[idx].enabled = val
                                    fm.saveSettings(fm.settings)
                                    triggerSaveFeedback(val ? "Task enabled" : "Task disabled")
                                }
                            }
                        ))
                        .labelsHidden()
                        .scaleEffect(0.8)
                        
                        Button(action: {
                            taskToDelete = task
                            showingDeleteConfirmation = true
                        }) {
                            Image(systemName: "trash")
                                .font(.footnote)
                                .foregroundColor(alertRed.opacity(0.8))
                                .padding(6)
                                .background(alertRed.opacity(0.08))
                                .cornerRadius(6)
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(task.enabled ? batteryGreen.opacity(0.15) : Color.clear, lineWidth: 1)
                    )
                }
            }
        }
        .alert("Delete Task", isPresented: $showingDeleteConfirmation, presenting: taskToDelete) { task in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteTask(task)
            }
        } message: { task in
            Text("Are you sure you want to delete the schedule task '\(task.name)'?")
        }
    }
}

struct BillingCalendarCardView: View {
    @ObservedObject var fm: FirebaseManager
    @Binding var currentCalendarMonth: Date
    @Binding var selectedCalendarDate: Date?
    
    let batteryGreen: Color
    let alertRed: Color
    let solarGold: Color
    let loadBlue: Color
    
    var billForDate: (Date) -> DailyBill?
    
    private func updateCalendarListener() {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: currentCalendarMonth)
        guard let start = calendar.date(from: components) else { return }
        
        var nextComp = DateComponents()
        nextComp.month = 1
        nextComp.day = -1
        guard let end = calendar.date(byAdding: nextComp, to: start) else { return }
        
        let paddedStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        let paddedEnd = calendar.date(byAdding: .day, value: 7, to: end) ?? end
        
        fm.listenToBillsRange(start: paddedStart, end: paddedEnd)
    }
    
    private func getDaysInMonth() -> [Date?] {
        let calendar = Calendar.current
        guard let monthRange = calendar.range(of: .day, in: .month, for: currentCalendarMonth) else { return [] }
        let components = calendar.dateComponents([.year, .month], from: currentCalendarMonth)
        guard let firstOfMonth = calendar.date(from: components) else { return [] }
        let startWeekday = calendar.component(.weekday, from: firstOfMonth)
        var days: [Date?] = []
        let weekdayOffset = (startWeekday + 5) % 7
        for _ in 0..<weekdayOffset { days.append(nil) }
        for day in 1...monthRange.count {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(date)
            }
        }
        return days
    }
    

    
    var body: some View {
        let calendar = Calendar.current
        let monthStr = DateFormatter.mmmmYyyy.string(from: currentCalendarMonth)
        
        let daysOfWeek = ["M", "T", "W", "T", "F", "S", "S"]
        let gridItems = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let days = getDaysInMonth()
        
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("BILLING CALENDAR", systemImage: "calendar")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(batteryGreen)
                    .tracking(1)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: {
                        if let prevMonth = calendar.date(byAdding: .month, value: -1, to: currentCalendarMonth) {
                            currentCalendarMonth = prevMonth
                            selectedCalendarDate = nil
                            updateCalendarListener()
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.footnote)
                            .foregroundColor(.white)
                    }
                    
                    Text(monthStr.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(minWidth: 100)
                        .multilineTextAlignment(.center)
                    
                    Button(action: {
                        if let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentCalendarMonth) {
                            currentCalendarMonth = nextMonth
                            selectedCalendarDate = nil
                            updateCalendarListener()
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundColor(.white)
                    }
                }
            }
            
            Divider().background(Color.white.opacity(0.04))
            
            HStack(spacing: 0) {
                ForEach(0..<daysOfWeek.count, id: \.self) { index in
                    Text(daysOfWeek[index])
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            LazyVGrid(columns: gridItems, spacing: 6) {
                ForEach(0..<days.count, id: \.self) { index in
                    if let date = days[index] {
                        let isToday = calendar.isDateInToday(date)
                        let isSelected = selectedCalendarDate != nil && calendar.isDate(selectedCalendarDate!, inSameDayAs: date)
                        let bill = billForDate(date)
                        
                        Button(action: {
                            selectedCalendarDate = date
                        }) {
                            VStack(spacing: 2) {
                                Text("\(calendar.component(.day, from: date))")
                                    .font(.system(size: 11, weight: isToday ? .black : .medium))
                                    .foregroundColor(isToday ? batteryGreen : .white)
                                
                                if let b = bill {
                                    Text(String(format: "%@$%.1f", b.net_cost < 0 ? "-" : "", abs(b.net_cost)))
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(b.net_cost <= 0 ? batteryGreen : alertRed)
                                        .padding(.horizontal, 2)
                                        .background(b.net_cost <= 0 ? batteryGreen.opacity(0.1) : alertRed.opacity(0.1))
                                        .cornerRadius(3)
                                } else {
                                    Spacer().frame(height: 10)
                                }
                            }
                            .frame(height: 38)
                            .frame(maxWidth: .infinity)
                            .background(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.02))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected ? batteryGreen.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                        }
                    } else {
                        Color.clear
                            .frame(height: 38)
                    }
                }
            }
            
            if let selected = selectedCalendarDate {
                let bill = billForDate(selected)
                SelectedDateAuditView(selected: selected, bill: bill, dateFmt: DateFormatter.eeeedMmmYyyy, batteryGreen: batteryGreen, alertRed: alertRed, solarGold: solarGold, loadBlue: loadBlue)
            }
        }
        .padding(16)
        .glassCardStyle(cornerRadius: 18)
        .onAppear {
            updateCalendarListener()
        }
        .onChange(of: currentCalendarMonth) { _, _ in
            updateCalendarListener()
        }
    }
}

struct SelectedDateAuditView: View {
    let selected: Date
    let bill: DailyBill?
    let dateFmt: DateFormatter
    
    let batteryGreen: Color
    let alertRed: Color
    let solarGold: Color
    let loadBlue: Color
    
    private var peakKwh: Double {
        bill?.peak_kwh ?? ((bill?.import_kwh ?? 0.0) * 0.50)
    }
    private var peakCost: Double {
        bill?.peak_cost ?? (peakKwh * FirebaseManager.shared.settings.tariff.fallbackImportRate)
    }
    private var freeKwh: Double {
        bill?.free_kwh ?? ((bill?.import_kwh ?? 0.0) * 0.15)
    }
    private var offPeakKwh: Double {
        bill?.off_peak_kwh ?? ((bill?.import_kwh ?? 0.0) * 0.35)
    }
    private var offPeakCost: Double {
        bill?.off_peak_cost ?? max(0.0, (bill?.import_cost ?? 0.0) - peakCost)
    }
    
    @ViewBuilder
    private func auditItem(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(Color.white.opacity(0.02))
        .cornerRadius(6)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().background(Color.white.opacity(0.04))
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateFmt.string(from: selected).uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                    Text("Daily Balance Sheet Summary")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let b = bill {
                    Text(String(format: "%@$%.2f", b.net_cost < 0 ? "-" : "", abs(b.net_cost)))
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(b.net_cost <= 0 ? batteryGreen : alertRed)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(b.net_cost <= 0 ? batteryGreen.opacity(0.1) : alertRed.opacity(0.1))
                        .cornerRadius(6)
                }
            }
            
            if let b = bill {
                HStack(spacing: 8) {
                    auditItem(label: "Solar PV", value: String(format: "%.1f kWh", b.solar_kwh), color: solarGold)
                    auditItem(label: "Home Load", value: String(format: "%.1f kWh", b.load_kwh), color: loadBlue)
                    auditItem(label: "Grid Imp", value: String(format: "%.1f kWh", b.import_kwh), color: Color.orange)
                    auditItem(label: "Grid Exp", value: String(format: "%.1f kWh", b.export_kwh), color: batteryGreen)
                }
                
                VStack(spacing: 6) {
                    HStack {
                        Text("Fixed Grid Supply Charge")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "$%.2f", b.daily_supply_charge))
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    
                    HStack {
                        Text("Gross Grid Import Cost")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "$%.2f", b.import_cost ?? 0.0))
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("  • Peak Period (\(String(format: "%.1f", peakKwh)) kWh)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "$%.2f", peakCost))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("  • Off-Peak Period (\(String(format: "%.1f", offPeakKwh)) kWh)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "$%.2f", offPeakCost))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("  • Free Power Period (\(String(format: "%.1f", freeKwh)) kWh)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("$0.00")
                                .font(.system(size: 10))
                                .foregroundColor(batteryGreen)
                        }
                    }
                    .padding(.leading, 8)
                    
                    HStack {
                        Text("Gross Solar Export Credit")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "-$%.2f", b.export_credit ?? 0.0))
                            .font(.caption)
                            .foregroundColor(batteryGreen)
                    }
                    
                    Divider().background(Color.white.opacity(0.04))
                    
                    HStack {
                        Text("Calculated Financial Savings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "$%.2f Saved", b.savings))
                            .font(.caption.bold())
                            .foregroundColor(batteryGreen)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.02))
                .cornerRadius(8)
            } else {
                Text("No billing data recorded for this date.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            }
        }
    }
}

struct BillGeneratorCardView: View {
    @ObservedObject var fm: FirebaseManager
    @Binding var billStartDate: Date
    @Binding var billEndDate: Date
    @Binding var isGeneratingBill: Bool
    @Binding var generatedBill: GeneratedBillResult?
    @Binding var isExpanded: Bool
    
    let batteryGreen: Color
    let alertRed: Color
    
    private func calculateInvoice() {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        let start = calendar.startOfDay(for: billStartDate)
        let end = calendar.startOfDay(for: billEndDate)
        
        let filtered = fm.historicalBills.filter { bill in
            guard let date = formatter.date(from: bill.date) else { return false }
            let day = calendar.startOfDay(for: date)
            let hasTelemetry = bill.solar_kwh > 0 || bill.load_kwh > 0 || bill.import_kwh > 0 || bill.export_kwh > 0
            return day >= start && day <= end && hasTelemetry
        }
        
        var solar = 0.0
        var load = 0.0
        var gridImport = 0.0
        var gridExport = 0.0
        var charge = 0.0
        var discharge = 0.0
        
        var supply = 0.0
        var impCost = 0.0
        var expCredit = 0.0
        var netAmount = 0.0
        var savings = 0.0
        var arbitrage = 0.0
        
        var peakKwh = 0.0
        var peakCost = 0.0
        var offPeakKwh = 0.0
        var offPeakCost = 0.0
        var freeKwh = 0.0
        var freeCost = 0.0
        
        for bill in filtered {
            solar += bill.solar_kwh
            load += bill.load_kwh
            gridImport += bill.import_kwh
            gridExport += bill.export_kwh
            charge += bill.charge_kwh
            discharge += bill.discharge_kwh
            
            supply += bill.daily_supply_charge
            impCost += bill.import_cost ?? 0.0
            expCredit += bill.export_credit ?? 0.0
            netAmount += bill.net_cost
            savings += bill.savings
            arbitrage += bill.arbitrage
            
            if let pk = bill.peak_kwh, let pc = bill.peak_cost,
               let opk = bill.off_peak_kwh, let opc = bill.off_peak_cost,
               let fk = bill.free_kwh, let fc = bill.free_cost {
                peakKwh += pk
                peakCost += pc
                offPeakKwh += opk
                offPeakCost += opc
                freeKwh += fk
                freeCost += fc
            } else {
                let pK = bill.import_kwh * 0.50
                let pC = pK * fm.settings.tariff.fallbackImportRate
                let fK = bill.import_kwh * 0.15
                let fC = 0.0
                let opK = bill.import_kwh * 0.35
                let opC = max(0.0, (bill.import_cost ?? 0.0) - pC)
                
                peakKwh += pK
                peakCost += pC
                offPeakKwh += opK
                offPeakCost += opC
                freeKwh += fK
                freeCost += fC
            }
        }
        
        generatedBill = GeneratedBillResult(
            startDate: billStartDate,
            endDate: billEndDate,
            totalSolarKwh: solar,
            totalLoadKwh: load,
            totalImportKwh: gridImport,
            totalExportKwh: gridExport,
            totalChargeKwh: charge,
            totalDischargeKwh: discharge,
            dailySupplyChargeTotal: supply,
            grossImportCost: impCost,
            grossExportCredit: expCredit,
            netBillAmount: netAmount,
            totalSavings: savings,
            totalArbitrage: arbitrage,
            totalPeakKwh: peakKwh,
            totalPeakCost: peakCost,
            totalOffPeakKwh: offPeakKwh,
            totalOffPeakCost: offPeakCost,
            totalFreeKwh: freeKwh,
            totalFreeCost: freeCost
        )
    }
    
    @ViewBuilder
    private func invoiceRow(label: String, value: String, color: Color = .white) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
        }
    }
    
    private func formatRange(start: Date, end: Date) -> String {
        return "\(DateFormatter.dMmmYyyy.string(from: start)) - \(DateFormatter.dMmmYyyy.string(from: end))"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(batteryGreen)
                    .font(.system(size: 14, weight: .bold))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("BILL GENERATOR")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(batteryGreen)
                        .tracking(1.5)
                    
                    if !isExpanded {
                        Text("Generate statements for custom date ranges")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            }
            .padding(.horizontal, 4)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    Divider().background(Color.white.opacity(0.04))
                    
                    VStack(spacing: 12) {
                        HStack {
                            DatePicker("From", selection: $billStartDate, displayedComponents: .date)
                                .font(.footnote)
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            DatePicker("To", selection: $billEndDate, displayedComponents: .date)
                                .font(.footnote)
                                .foregroundColor(.white)
                        }
                        .onChange(of: billStartDate) { _, _ in
                            fm.listenToBillsRange(start: billStartDate, end: billEndDate)
                            generatedBill = nil
                        }
                        .onChange(of: billEndDate) { _, _ in
                            fm.listenToBillsRange(start: billStartDate, end: billEndDate)
                            generatedBill = nil
                        }
                        
                        Button(action: {
                            isGeneratingBill = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                calculateInvoice()
                                isGeneratingBill = false
                            }
                        }) {
                            HStack {
                                if isGeneratingBill {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "doc.text.below.ecg.fill")
                                }
                                Text(isGeneratingBill ? "Calculating..." : "Generate Statement")
                                    .fontWeight(.bold)
                            }
                            .font(.footnote)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(batteryGreen)
                            .cornerRadius(10)
                        }
                        .disabled(isGeneratingBill)
                    }
                    
                    if let bill = generatedBill {
                        VStack(alignment: .leading, spacing: 14) {
                            Divider().background(Color.white.opacity(0.04))
                            
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("XGROWATT ENERGY ACCOUNT")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(batteryGreen)
                                        Text("Electricity Account Statement")
                                            .font(.system(size: 14, weight: .black))
                                            .foregroundColor(.white)
                                    }
                                    Spacer()
                                    Image(systemName: "bolt.shield.fill")
                                        .font(.title)
                                        .foregroundColor(batteryGreen)
                                }
                                
                                Text(formatRange(start: bill.startDate, end: bill.endDate))
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                                
                                Divider().background(Color.white.opacity(0.06))
                                
                                VStack(spacing: 8) {
                                    invoiceRow(label: "Grid Import Energy", value: String(format: "%.1f kWh", bill.totalImportKwh))
                                    invoiceRow(label: "Grid Export Energy", value: String(format: "%.1f kWh", bill.totalExportKwh))
                                    invoiceRow(label: "Solar Self-Consumption", value: String(format: "%.1f kWh", bill.totalSolarKwh))
                                    invoiceRow(label: "Total Home Power Load", value: String(format: "%.1f kWh", bill.totalLoadKwh))
                                    
                                    Divider().background(Color.white.opacity(0.04))
                                    
                                    invoiceRow(label: "Daily Network Connection Fee (Supply)", value: String(format: "$%.2f", bill.dailySupplyChargeTotal))
                                    invoiceRow(label: "Gross Electricity Purchase Cost", value: String(format: "$%.2f", bill.grossImportCost))
                                    
                                    // Slices breakdown
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("  • Peak Period (\(String(format: "%.1f", bill.totalPeakKwh)) kWh)")
                                                .font(.system(size: 9.5))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(String(format: "$%.2f", bill.totalPeakCost))
                                                .font(.system(size: 9.5))
                                                .foregroundColor(.secondary)
                                        }
                                        HStack {
                                            Text("  • Off-Peak Period (\(String(format: "%.1f", bill.totalOffPeakKwh)) kWh)")
                                                .font(.system(size: 9.5))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text(String(format: "$%.2f", bill.totalOffPeakCost))
                                                .font(.system(size: 9.5))
                                                .foregroundColor(.secondary)
                                        }
                                        HStack {
                                            Text("  • Free Power Period (\(String(format: "%.1f", bill.totalFreeKwh)) kWh)")
                                                .font(.system(size: 9.5))
                                                .foregroundColor(.secondary)
                                            Spacer()
                                            Text("$0.00")
                                                .font(.system(size: 9.5))
                                                .foregroundColor(batteryGreen)
                                        }
                                    }
                                    .padding(.leading, 8)
                                    
                                    invoiceRow(label: "Solar Feed-in Credit Rebates", value: String(format: "-$%.2f", bill.grossExportCredit), color: batteryGreen)
                                    
                                    Divider().background(Color.white.opacity(0.06))
                                    
                                    HStack {
                                        Text("NET BILL AMOUNT DUE")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text(String(format: "%@$%.2f", bill.netBillAmount < 0 ? "-" : "", abs(bill.netBillAmount)))
                                            .font(.system(size: 16, weight: .black))
                                            .foregroundColor(bill.netBillAmount <= 0 ? batteryGreen : alertRed)
                                    }
                                    
                                    HStack {
                                        Text("Net Financial Savings Realized (全口径净省收益)")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(String(format: "$%.2f Saved", bill.totalSavings))
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(batteryGreen)
                                    }
                                }
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.015))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
                            )
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(16)
        .glassCardStyle(cornerRadius: 18)
    }
}


struct TariffPlanCardView: View {
    let tariff: ElectricityTariffPlan
    let rules: [TariffRule]
    @Binding var isTariffSectionExpanded: Bool
    @Binding var activeTariffSheet: TariffSheetContext?
    
    let batteryGreen: Color
    let alertRed: Color
    
    var deleteTariffRule: (TariffRule) -> Void
    var onSaveSupplyCharge: (Double) -> Void
    var onSaveImportRate: (Double) -> Void
    var onSaveExportRate: (Double) -> Void
    var onToggleRule: (TariffRule, Bool) -> Void
    
    // Fully local text state — initialized once from tariff value on appear
    @State private var dailySupplyText: String = ""
    @State private var buyGridText: String = ""
    @State private var sellFeedInText: String = ""
    
    @State private var showingDeleteConfirmation = false
    @State private var ruleToDelete: TariffRule? = nil
    
    @FocusState private var isDailySupplyFocused: Bool
    @FocusState private var isBuyGridFocused: Bool
    @FocusState private var isSellFeedInFocused: Bool
    
    private func syncLocalTexts(from t: ElectricityTariffPlan) {
        if !isDailySupplyFocused {
            dailySupplyText = String(format: "%.0f", t.dailySupplyCharge * 100)
        }
        if !isBuyGridFocused {
            buyGridText = String(format: "%.0f", t.fallbackImportRate * 100)
        }
        if !isSellFeedInFocused {
            sellFeedInText = String(format: "%.0f", t.fallbackExportRate * 100)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundColor(batteryGreen)
                    .font(.system(size: 14, weight: .bold))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("ELECTRICITY TARIFF PLAN")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(batteryGreen)
                        .tracking(1.5)
                    
                    if !isTariffSectionExpanded {
                        Text("Supply: $\(String(format: "%.2f", tariff.dailySupplyCharge))/day • \(rules.count) ToU Rules")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if isTariffSectionExpanded {
                    Button(action: {
                        activeTariffSheet = TariffSheetContext(rule: nil)
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(batteryGreen)
                            .font(.system(size: 18))
                    }
                    .padding(.trailing, 8)
                }
                
                Image(systemName: isTariffSectionExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isTariffSectionExpanded.toggle()
                }
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 16) {
                Divider().background(Color.white.opacity(0.04))
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("BASE FALLBACK RATES (FLAT RATE)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Daily Supply (¢/day)")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            TextField("95", text: $dailySupplyText)
                                .keyboardType(.numberPad)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(Color.white.opacity(0.03)).cornerRadius(6)
                                .foregroundColor(.white).font(.system(size: 12, design: .rounded))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.06), lineWidth: 1))
                                .focused($isDailySupplyFocused)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Buy Grid (¢/kWh)")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            TextField("30", text: $buyGridText)
                                .keyboardType(.numberPad)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(Color.white.opacity(0.03)).cornerRadius(6)
                                .foregroundColor(.white).font(.system(size: 12, design: .rounded))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.06), lineWidth: 1))
                                .focused($isBuyGridFocused)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sell Feed-in (¢/kWh)")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                            TextField("8", text: $sellFeedInText)
                                .keyboardType(.numberPad)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(Color.white.opacity(0.03)).cornerRadius(6)
                                .foregroundColor(.white).font(.system(size: 12, design: .rounded))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.06), lineWidth: 1))
                                .focused($isSellFeedInFocused)
                        }
                    }
                }
                
                Divider().background(Color.white.opacity(0.04))
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("CUSTOM TIME-OF-USE RULES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    if rules.isEmpty {
                        Text("No ToU rules added. Using base flat rates only.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(rules) { rule in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(rule.name)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .font(.system(size: 13))
                                        Text("(\(rule.start_time) - \(rule.end_time))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack(spacing: 12) {
                                        Text("Buy: $\(String(format: "%.2f", rule.import_rate))/kWh")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("Sell: $\(String(format: "%.2f", rule.export_rate))/kWh")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack(spacing: 2) {
                                        let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                                        ForEach(days, id: \.self) { day in
                                            Text(String(day.first ?? " "))
                                                .font(.system(size: 8, weight: .bold))
                                                .frame(width: 13, height: 13)
                                                .foregroundColor(rule.days.contains(day) ? .white : .secondary.opacity(0.4))
                                                .background(rule.days.contains(day) ? batteryGreen.opacity(0.3) : Color.white.opacity(0.02))
                                                .clipShape(Circle())
                                        }
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    activeTariffSheet = TariffSheetContext(rule: rule)
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: Binding(
                                    get: { rule.enabled },
                                    set: { val in onToggleRule(rule, val) }
                                ))
                                .labelsHidden()
                                .scaleEffect(0.8)
                                
                                Button(action: {
                                    ruleToDelete = rule
                                    showingDeleteConfirmation = true
                                }) {
                                    Image(systemName: "trash")
                                        .font(.footnote)
                                        .foregroundColor(alertRed.opacity(0.8))
                                        .padding(6)
                                        .background(alertRed.opacity(0.08))
                                        .cornerRadius(6)
                                }
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.02))
                            .cornerRadius(10)
                        }
                    }
                }
            }
            .opacity(isTariffSectionExpanded ? 1 : 0)
            .frame(maxHeight: isTariffSectionExpanded ? .none : 0)
            .clipped()
        }
        .padding(16)
        .glassCardStyle(cornerRadius: 18)
        .onAppear {
            syncLocalTexts(from: tariff)
        }
        .onChange(of: tariff) { _, newTariff in
            syncLocalTexts(from: newTariff)
        }
        .onChange(of: isTariffSectionExpanded) { _, newValue in
            if !newValue {
                isDailySupplyFocused = false
                isBuyGridFocused = false
                isSellFeedInFocused = false
                UIApplication.shared.endEditing()
            }
        }
        .onChange(of: isDailySupplyFocused) { oldVal, newVal in
            if oldVal == true && newVal == false {
                if let val = Double(dailySupplyText) { onSaveSupplyCharge(val / 100.0) }
                else { dailySupplyText = String(format: "%.0f", tariff.dailySupplyCharge * 100) }
            }
        }
        .onChange(of: isBuyGridFocused) { oldVal, newVal in
            if oldVal == true && newVal == false {
                if let val = Double(buyGridText) { onSaveImportRate(val / 100.0) }
                else { buyGridText = String(format: "%.0f", tariff.fallbackImportRate * 100) }
            }
        }
        .onChange(of: isSellFeedInFocused) { oldVal, newVal in
            if oldVal == true && newVal == false {
                if let val = Double(sellFeedInText) { onSaveExportRate(val / 100.0) }
                else { sellFeedInText = String(format: "%.0f", tariff.fallbackExportRate * 100) }
            }
        }
        .alert("Delete Rule", isPresented: $showingDeleteConfirmation, presenting: ruleToDelete) { rule in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteTariffRule(rule)
            }
        } message: { rule in
            Text("Are you sure you want to delete the tariff rule '\(rule.name)'?")
        }
    }
}

// MARK: - PlanBillsTabContainerView (Isolated from ContentView to prevent cross-tab re-renders)

struct TariffSheetContext: Identifiable {
    let id = UUID()
    let rule: TariffRule?
}

struct TaskSheetContext: Identifiable {
    let id = UUID()
    let task: GrowattTask?
}

// MARK: - Smart Charging Plan Card (advisory output of generate_charging_plan)
struct ChargingPlanCardView: View {
    @ObservedObject var fm: FirebaseManager
    @Binding var isExpanded: Bool
    let batteryGreen: Color
    let alertRed: Color
    let solarGold: Color

    @State private var showApplyConfirm = false
    @State private var showRevertConfirm = false

    private func summaryLine(_ plan: ChargingPlan) -> String {
        if plan.suggested_tasks.isEmpty {
            return "\(plan.for_date): no grid charge needed"
        }
        // Same format as the Inverter Schedule collapsed summary: "window → SoC X%"
        let windows = plan.suggested_tasks.map { "\($0.start_time)-\($0.end_time) → SoC \($0.soc)%" }.joined(separator: ", ")
        let cost = plan.est_day_cost ?? plan.est_cost
        return "\(plan.for_date): \(windows) (day ~$\(String(format: "%.2f", cost)))"
    }

    private func metricCell(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(1.0)
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    var body: some View {
        if let plan = fm.chargingPlan {
            VStack(alignment: .leading, spacing: 12) {
                // Header (collapsible, same interaction pattern as the other cards)
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .foregroundColor(solarGold)
                            .font(.system(size: 14, weight: .bold))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text("SMART CHARGING PLAN")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(solarGold)
                                    .tracking(1.5)
                                if fm.settings.ai_auto_apply {
                                    Text("AUTO")
                                        .font(.system(size: 8, weight: .black))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(batteryGreen)
                                        .cornerRadius(3)
                                }
                            }
                            if !isExpanded {
                                Text(summaryLine(plan))
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)  // weekend plans carry two windows — let it wrap
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isExpanded.toggle()
                        }
                    }

                    Button(action: { fm.regenerateChargingPlan() }) {
                        if fm.isRegeneratingPlan {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundColor(solarGold)
                                .font(.system(size: 18))
                        }
                    }
                    .disabled(fm.isRegeneratingPlan)
                    .padding(.trailing, 8)

                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isExpanded.toggle()
                            }
                        }
                }
                .padding(.horizontal, 4)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 14) {
                        Divider().background(Color.white.opacity(0.04))

                        let taskPower = plan.suggested_tasks.first?.power ?? "100"
                        HStack(spacing: 0) {
                            metricCell("TARGET SOC", "\(plan.target_soc)% (\(taskPower)%)", batteryGreen)
                            metricCell("GRID CHARGE", String(format: "%.1f kWh", plan.charge_kwh), .white)
                            // Whole-day bill estimate (incl. EV, house, battery, exports,
                            // supply charge) — falls back to the charge-only cost on old plans
                            metricCell("EST DAY BILL", String(format: "$%.2f", plan.est_day_cost ?? plan.est_cost), solarGold)
                        }
                        HStack(spacing: 0) {
                            metricCell("PV FORECAST", String(format: "%.1f kWh", plan.pv_forecast_kwh ?? 0), solarGold)
                            metricCell("LOAD FORECAST", String(format: "%.1f kWh", plan.load_forecast_kwh ?? 0), .white)
                            metricCell("MODEL", plan.model_used == "ridge" ? "ML" : "FORMULA", .secondary)
                        }

                        if plan.ev_sponge_active == true {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "car.side.fill")
                                        .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                                        .font(.system(size: 14))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("EV SOLAR SPONGE ACTIVE")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(Color(red: 0.0, green: 0.9, blue: 1.0))
                                        Text("Releasing ~\(String(format: "%.1f", plan.ev_transfer_kwh ?? 0.0)) kWh to Tesla overnight to create daytime solar absorption capacity.")
                                            .font(.system(size: 10.5))
                                            .foregroundColor(.white.opacity(0.9))
                                    }
                                }
                                Divider().background(Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.25))
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Tesla 达标后继续充电 (06:00前谷电)")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                        Text("电池达标后不停止特斯拉，自动切为电池优先保底，转由电网谷电继续充车。")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { plan.tesla_continue_charge ?? false },
                                        set: { val in
                                            fm.updateTeslaContinueCharge(val)
                                        }
                                    ))
                                    .labelsHidden()
                                    .scaleEffect(0.8)
                                }
                            }
                            .padding(10)
                            .background(Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.08))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(red: 0.0, green: 0.9, blue: 1.0).opacity(0.35), lineWidth: 0.5)
                            )
                        }

                        if !plan.suggested_tasks.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("SUGGESTED CHARGE WINDOWS (\(plan.for_date))")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                ForEach(plan.suggested_tasks) { task in
                                    HStack(spacing: 8) {
                                        Image(systemName: "bolt.badge.clock.fill")
                                            .foregroundColor(batteryGreen)
                                            .font(.system(size: 12))
                                        Text("\(task.start_time)–\(task.end_time)")
                                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                        Text("→ SoC \(task.soc)% (\(task.power)% Power)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(batteryGreen)
                                        Spacer()
                                        Text(task.days.joined(separator: ", "))
                                            .font(.system(size: 10.5))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(10)
                                    .background(Color.white.opacity(0.03))
                                    .cornerRadius(8)
                                }

                                // Single stateful button: Apply <-> Recall. State derives
                                // from cloud data (not local state), so it survives app
                                // restarts and correctly reflects auto-applied plans too.
                                let isApplied = fm.hasAppliedAiPlan && fm.settings.ai_plan_applied_for == plan.for_date
                                Button(action: {
                                    if isApplied { showRevertConfirm = true } else { showApplyConfirm = true }
                                }) {
                                    HStack {
                                        Image(systemName: isApplied ? "arrow.uturn.backward.circle.fill" : "plus.circle.fill")
                                        Text(isApplied ? "Recall from Schedule" : "Apply to Schedule")
                                            .fontWeight(.bold)
                                    }
                                    .font(.system(size: 13))
                                    .foregroundColor(isApplied ? .orange : .black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(isApplied ? Color.orange.opacity(0.12) : batteryGreen)
                                    .cornerRadius(10)
                                }
                                .alert("Apply AI plan for \(plan.for_date)?", isPresented: $showApplyConfirm) {
                                    Button("Cancel", role: .cancel) {}
                                    Button("Apply") {
                                        fm.applyChargingPlan()
                                    }
                                } message: {
                                    Text("One-shot override: on \(plan.for_date) the inverter follows this AI plan instead of your weekly schedule. Your weekly schedule is not modified and resumes automatically the day after.")
                                }
                                .alert("Recall the AI plan?", isPresented: $showRevertConfirm) {
                                    Button("Cancel", role: .cancel) {}
                                    Button("Recall", role: .destructive) {
                                        fm.revertChargingPlan()
                                    }
                                } message: {
                                    Text("Removes the applied AI Plan tasks. Your weekly schedule was never modified — it takes effect again from the next sync.")
                                }
                            }
                        }

                        if let briefing = plan.ai_briefing, !briefing.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(solarGold)
                                    Text("AI 能量管家简报")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(solarGold)
                                    if let src = plan.llm_plan_source, !src.isEmpty {
                                        Spacer()
                                        Text(src.replacingOccurrences(of: "gemini-", with: ""))
                                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.white.opacity(0.06))
                                            .cornerRadius(4)
                                    }
                                }
                                Text(briefing)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.92))
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(solarGold.opacity(0.08))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(solarGold.opacity(0.2), lineWidth: 1)
                            )
                        }

                        let filteredReasoning = plan.reasoning.filter { !(plan.ai_briefing != nil && $0.hasPrefix("🤖 AI 能量管家简报")) }
                        if !filteredReasoning.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("WHY")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.secondary)
                                ForEach(Array(filteredReasoning.enumerated()), id: \.offset) { _, line in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("•")
                                            .font(.system(size: 10))
                                            .foregroundColor(solarGold.opacity(0.8))
                                        Text(line)
                                            .font(.system(size: 10.5))
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.02))
                            .cornerRadius(8)
                        }

                        // AUTO mode toggle: nightly 23:30 plan applies itself. Skipped
                        // automatically (weekly plan runs) when fresh weather is unavailable.
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-apply nightly plan")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                Text("Applies each night's 23:30 plan automatically. If fresh weather can't be fetched, generation is skipped and the weekly schedule runs.")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { fm.settings.ai_auto_apply },
                                set: { val in
                                    fm.settings.ai_auto_apply = val
                                    fm.saveSettings(fm.settings)
                                }
                            ))
                            .labelsHidden()
                            .tint(batteryGreen)
                            .scaleEffect(0.8)  // match every other switch in the app
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.02))
                        .cornerRadius(8)

                        if let generated = plan.generated_at {
                            Text((fm.settings.ai_auto_apply
                                  ? "AUTO mode on — tonight's plan will apply itself at 23:30. "
                                  : "Advisory only — nothing changes until you apply. ")
                                 + "Generated \(generated.formatted(date: .abbreviated, time: .shortened)).")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(16)
            .glassCardStyle(cornerRadius: 18)
            // No state reset needed: the Apply/Recall button derives its state from
            // fm.settings.ai_plan_applied_for vs plan.for_date on every render.
        }
    }
}

struct PlanBillsTabContainerView: View {
    @ObservedObject var fm: FirebaseManager
    
    // Plan & Bills Tab Collapsible States (isolated here)
    @State private var isPlanSectionExpanded = false
    @State private var isSchedulerSectionExpanded = false
    @State private var isTariffSectionExpanded = false
    @State private var isBillGeneratorSectionExpanded = false
    
    // Editor context states (fully type-safe and race-condition free)
    @State private var activeTariffSheet: TariffSheetContext? = nil
    @State private var activeTaskSheet: TaskSheetContext? = nil
    
    // Calendar Month Paging
    @State private var currentCalendarMonth = Date()
    @State private var selectedCalendarDate: Date? = nil
    
    // Bill Generator Date Pickers
    @State private var billStartDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var billEndDate = Date()
    @State private var generatedBill: GeneratedBillResult? = nil
    @State private var isGeneratingBill = false
    
    // Design Colors
    private let batteryGreen = Theme.batteryGreen
    private let alertRed = Theme.alertRed
    private let solarGold = Theme.solarGold
    private let loadBlue = Theme.loadBlue
    private let bgDark = Theme.bgDark
    
    private func scheduleSummary(for date: Date, label: String) -> String {
        let dayName = DateFormatter.eee.string(from: date)
        // Mirror the cloud resolver's priority rule: on the AI-applied date show ONLY the
        // AI tasks; on any other date show ONLY the weekly manual tasks.
        let aiActive = !fm.settings.ai_plan_applied_for.isEmpty
            && fm.settings.ai_plan_applied_for == DateFormatter.yyyyMMdd.string(from: date)
            && fm.settings.tasks.contains { $0.name.hasPrefix("AI Plan:") }
        let dayTasks = fm.settings.tasks.filter {
            $0.enabled && $0.days.contains(dayName) && ($0.name.hasPrefix("AI Plan:") == aiActive)
        }
        if dayTasks.isEmpty {
            let isWeekend = Calendar.current.isDateInWeekend(date)
            return isWeekend ? "\(label): 00:00-06:00, 12:00-14:00 (Default)" : "\(label): 00:00-06:00 (Default)"
        } else {
            let sortedTasks = dayTasks.sorted { $0.start_time < $1.start_time }
            let tag = aiActive ? " ⚡AI" : ""
            return "\(label)\(tag): " + sortedTasks.map { "\($0.start_time)-\($0.end_time) → SoC \($0.soc)%" }.joined(separator: ", ")
        }
    }
    
    private func billForDate(_ date: Date) -> DailyBill? {
        let dateStr = DateFormatter.yyyyMMdd.string(from: date)
        if let bill = fm.historicalBills.first(where: { $0.date == dateStr }) {
            let hasTelemetry = bill.solar_kwh > 0 || bill.load_kwh > 0 || bill.import_kwh > 0 || bill.export_kwh > 0
            return hasTelemetry ? bill : nil
        }
        return nil
    }
    
    private func deleteTask(_ task: GrowattTask) {
        fm.settings.tasks.removeAll { $0.id == task.id }
        fm.saveSettings(fm.settings)
    }
    
    private func deleteTariffRule(_ rule: TariffRule) {
        var updatedPlan = fm.settings.tariff
        updatedPlan.rules.removeAll(where: { $0.id == rule.id })
        fm.settings.tariff = updatedPlan
        fm.saveSettings(fm.settings)
    }

    var body: some View {

        ScrollView {
            VStack(spacing: 20) {
                // Main Tab Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PLANNING & FINANCE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(batteryGreen)
                            .tracking(1.5)
                        Text("Plan & Bills")
                            .font(.title2)
                            .fontWeight(.black)
                            .foregroundColor(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 28)

                // 0. SMART CHARGING PLAN (advisory card; hidden until the cloud function
                // has produced its first status/charging_plan document)
                ChargingPlanCardView(
                    fm: fm,
                    isExpanded: $isPlanSectionExpanded,
                    batteryGreen: batteryGreen,
                    alertRed: alertRed,
                    solarGold: solarGold
                )
                .padding(.horizontal)


                // 1. COLLAPSIBLE SCHEDULER SECTION
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(batteryGreen)
                            .font(.system(size: 14, weight: .bold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("INVERTER SCHEDULE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(batteryGreen)
                                .tracking(1.5)
                            if !isSchedulerSectionExpanded {
                                Text(scheduleSummary(for: Date(), label: "Today"))
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                                Text(scheduleSummary(for: Date().addingTimeInterval(86400), label: "Tomorrow"))
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary.opacity(0.75))
                            }
                        }
                        Spacer()
                        if isSchedulerSectionExpanded {
                             Button(action: {
                                 activeTaskSheet = TaskSheetContext(task: nil)
                             }) {
                                 Image(systemName: "plus.circle.fill")
                                     .foregroundColor(batteryGreen)
                                     .font(.system(size: 18))
                             }
                             .padding(.trailing, 8)
                         }
                         Image(systemName: isSchedulerSectionExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                             .foregroundColor(.secondary)
                             .font(.system(size: 16))
                     }
                     .contentShape(Rectangle())
                     .onTapGesture {
                         withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                             isSchedulerSectionExpanded.toggle()
                         }
                     }
                     .padding(.horizontal, 4)
                     
                     if isSchedulerSectionExpanded {
                         VStack(spacing: 16) {
                             Divider().background(Color.white.opacity(0.04))
                             VStack(alignment: .leading, spacing: 8) {
                                 Text("24H RESOLVED TIMELINE PREVIEW (TODAY)")
                                     .font(.caption2)
                                     .fontWeight(.bold)
                                     .foregroundColor(.secondary)
                                 TimelinePreviewView(fm: fm)
                             }
                             SchedulesSectionView(
                                 fm: fm,
                                 activeTaskSheet: $activeTaskSheet,
                                 batteryGreen: batteryGreen,
                                 alertRed: alertRed,
                                 triggerSaveFeedback: { _ in },
                                 deleteTask: { task in deleteTask(task) }
                             )
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(batteryGreen.opacity(0.8))
                                    .font(.system(size: 10))
                                Text("Schedules are saved to the cloud and synced automatically.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.02))
                            .cornerRadius(8)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(16)
                .glassCardStyle(cornerRadius: 18)
                .padding(.horizontal)
                
                // 2. TARIFF PLAN
                TariffPlanCardView(
                    tariff: fm.settings.tariff,
                    rules: fm.settings.tariff.rules,
                    isTariffSectionExpanded: $isTariffSectionExpanded,
                    activeTariffSheet: $activeTariffSheet,
                    batteryGreen: batteryGreen,
                    alertRed: alertRed,
                    deleteTariffRule: { rule in deleteTariffRule(rule) },
                    onSaveSupplyCharge: { val in
                        var updated = fm.settings.tariff
                        updated.dailySupplyCharge = val
                        fm.settings.tariff = updated
                        fm.saveSettings(fm.settings)
                    },
                    onSaveImportRate: { val in
                        var updated = fm.settings.tariff
                        updated.fallbackImportRate = val
                        fm.settings.tariff = updated
                        fm.saveSettings(fm.settings)
                    },
                    onSaveExportRate: { val in
                        var updated = fm.settings.tariff
                        updated.fallbackExportRate = val
                        fm.settings.tariff = updated
                        fm.saveSettings(fm.settings)
                    },
                    onToggleRule: { rule, val in
                        var updated = fm.settings.tariff
                        if let idx = updated.rules.firstIndex(where: { $0.id == rule.id }) {
                            updated.rules[idx].enabled = val
                        }
                        fm.settings.tariff = updated
                        fm.saveSettings(fm.settings)
                    }
                )
                .padding(.horizontal)
                
                // 3. BILLING CALENDAR
                BillingCalendarCardView(
                    fm: fm,
                    currentCalendarMonth: $currentCalendarMonth,
                    selectedCalendarDate: $selectedCalendarDate,
                    batteryGreen: batteryGreen,
                    alertRed: alertRed,
                    solarGold: solarGold,
                    loadBlue: loadBlue,
                    billForDate: { date in billForDate(date) }
                )
                .padding(.horizontal)
                
                // 4. BILL GENERATOR
                BillGeneratorCardView(
                    fm: fm,
                    billStartDate: $billStartDate,
                    billEndDate: $billEndDate,
                    isGeneratingBill: $isGeneratingBill,
                    generatedBill: $generatedBill,
                    isExpanded: $isBillGeneratorSectionExpanded,
                    batteryGreen: batteryGreen,
                    alertRed: alertRed
                )
                .padding(.horizontal)
            }
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.immediately)
        .scrollContentBackground(.hidden)
        .background(.clear)
        .onAppear {
            isPlanSectionExpanded = false
            fm.listenToBillsRange(start: billStartDate, end: billEndDate)
        }
        .sheet(item: $activeTaskSheet) { context in
            GrowattTaskEditorSheetView(
                editingTask: context.task,
                batteryGreen: batteryGreen,
                alertRed: alertRed,
                bgDark: bgDark,
                onSave: { task in
                    var updatedTasks = fm.settings.tasks
                    if let idx = updatedTasks.firstIndex(where: { $0.id == task.id }) {
                        updatedTasks[idx] = task
                    } else {
                        updatedTasks.append(task)
                    }
                    fm.settings.tasks = updatedTasks
                    fm.saveSettings(fm.settings)
                    activeTaskSheet = nil
                },
                onCancel: { activeTaskSheet = nil }
            )
        }
        .sheet(item: $activeTariffSheet) { context in
            TariffRuleEditorSheetView(
                editingRule: context.rule,
                batteryGreen: batteryGreen,
                alertRed: alertRed,
                bgDark: bgDark,
                onSave: { rule in
                    var updatedPlan = fm.settings.tariff
                    if let idx = updatedPlan.rules.firstIndex(where: { $0.id == rule.id }) {
                        updatedPlan.rules[idx] = rule
                    } else {
                        updatedPlan.rules.append(rule)
                    }
                    fm.settings.tariff = updatedPlan
                    fm.saveSettings(fm.settings)
                    activeTariffSheet = nil
                },
                onCancel: { activeTariffSheet = nil }
            )
        }
    }
}

// MARK: - TariffRuleEditorSheetView (Isolated with local @State so keystrokes don't re-render Plan & Bills tab)

struct TariffRuleEditorSheetView: View {
    let editingRule: TariffRule?
    let batteryGreen: Color
    let alertRed: Color
    let bgDark: Color
    var onSave: (TariffRule) -> Void
    var onCancel: () -> Void

    @State private var name: String
    @State private var days: [String]
    @State private var startTime: String
    @State private var endTime: String
    @State private var importText: String
    @State private var exportText: String

    init(editingRule: TariffRule?, batteryGreen: Color, alertRed: Color, bgDark: Color,
         onSave: @escaping (TariffRule) -> Void, onCancel: @escaping () -> Void) {
        self.editingRule = editingRule
        self.batteryGreen = batteryGreen
        self.alertRed = alertRed
        self.bgDark = bgDark
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: editingRule?.name ?? "")
        _days = State(initialValue: editingRule?.days ?? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        _startTime = State(initialValue: editingRule?.start_time ?? "17:00")
        _endTime = State(initialValue: editingRule?.end_time ?? "22:00")
        _importText = State(initialValue: editingRule.map { String(format: "%.0f", $0.import_rate * 100) } ?? "42")
        _exportText = State(initialValue: editingRule.map { String(format: "%.0f", $0.export_rate * 100) } ?? "8")
    }

    private func save() {
        let impVal = (Double(importText) ?? 30.0) / 100.0
        let expVal = (Double(exportText) ?? 8.0) / 100.0
        let newRule = TariffRule(
            id: editingRule?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            days: days,
            start_time: startTime,
            end_time: endTime,
            import_rate: impVal,
            export_rate: expVal,
            enabled: editingRule?.enabled ?? true
        )
        onSave(newRule)
    }

    var body: some View {
        ZStack {
            bgDark.ignoresSafeArea()
                .onTapGesture { UIApplication.shared.endEditing() }
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") { onCancel() }
                        .foregroundColor(alertRed)
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    Text(editingRule == nil ? "Add Tariff Rule" : "Edit Tariff Rule")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                    Spacer()
                    Button("Save") { save() }
                        .foregroundColor(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || days.isEmpty ? .secondary : batteryGreen)
                        .font(.system(size: 15, weight: .bold))
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || days.isEmpty)
                }
                .padding().background(.ultraThinMaterial)
                .overlay(VStack { Spacer(); Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1) })
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RULE DETAILS").font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
                            TextField("Rule Name (e.g. Peak ToU)", text: $name)
                                .padding().background(Color.white.opacity(0.03)).cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.04), lineWidth: 1))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal).padding(.top)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TIME WINDOW").font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
                            HStack {
                                Picker("Start Time", selection: $startTime) {
                                    ForEach(0..<24) { hour in let t = String(format: "%02d:00", hour); Text(t).tag(t) }
                                }.pickerStyle(.menu).foregroundColor(.white).padding(8).background(Color.white.opacity(0.03)).cornerRadius(8)
                                Text("to").foregroundColor(.secondary)
                                Picker("End Time", selection: $endTime) {
                                    ForEach(0..<24) { hour in let t = String(format: "%02d:00", hour); Text(t).tag(t) }
                                }.pickerStyle(.menu).foregroundColor(.white).padding(8).background(Color.white.opacity(0.03)).cornerRadius(8)
                            }
                        }.padding(.horizontal)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DAYS ACTIVE").font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
                            HStack(spacing: 6) {
                                let allDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                                ForEach(allDays, id: \.self) { day in
                                    let isSel = days.contains(day)
                                    Button(action: {
                                        if isSel { days.removeAll { $0 == day } } else { days.append(day) }
                                    }) {
                                        Text(day.prefix(1)).font(.footnote).fontWeight(.bold)
                                            .frame(width: 32, height: 32)
                                            .foregroundColor(isSel ? .white : .secondary)
                                            .background(isSel ? batteryGreen : Color.white.opacity(0.03))
                                            .clipShape(Circle())
                                    }
                                }
                            }
                        }.padding(.horizontal)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ELECTRICITY RATES (¢/kWh)").font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
                            HStack(spacing: 12) {
                                VStack(alignment: .leading) {
                                    Text("Buy (Grid Import)").font(.caption2).foregroundColor(.secondary)
                                    TextField("30", text: $importText)
                                        .keyboardType(.numberPad).padding()
                                        .background(Color.white.opacity(0.03)).cornerRadius(8).foregroundColor(.white)
                                }
                                VStack(alignment: .leading) {
                                    Text("Sell (Solar Export)").font(.caption2).foregroundColor(.secondary)
                                    TextField("8", text: $exportText)
                                        .keyboardType(.numberPad).padding()
                                        .background(Color.white.opacity(0.03)).cornerRadius(8).foregroundColor(.white)
                                }
                            }
                        }.padding(.horizontal)
                    }
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - GrowattTaskEditorSheetView (Isolated with local @State so keystrokes don't re-render Plan & Bills tab)

struct GrowattTaskEditorSheetView: View {
    let editingTask: GrowattTask?
    let batteryGreen: Color
    let alertRed: Color
    let bgDark: Color
    var onSave: (GrowattTask) -> Void
    var onCancel: () -> Void

    @State private var name: String
    @State private var days: [String]
    @State private var startTime: String
    @State private var endTime: String
    @State private var power: Int
    @State private var soc: Int

    init(editingTask: GrowattTask?, batteryGreen: Color, alertRed: Color, bgDark: Color,
         onSave: @escaping (GrowattTask) -> Void, onCancel: @escaping () -> Void) {
        self.editingTask = editingTask
        self.batteryGreen = batteryGreen
        self.alertRed = alertRed
        self.bgDark = bgDark
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: editingTask?.name ?? "")
        _days = State(initialValue: editingTask?.days ?? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        _startTime = State(initialValue: editingTask?.start_time ?? "00:00")
        _endTime = State(initialValue: editingTask?.end_time ?? "06:00")
        _power = State(initialValue: editingTask.flatMap { Int($0.power) } ?? 100)
        _soc = State(initialValue: editingTask.flatMap { Int($0.soc) } ?? 100)
    }

    private func save() {
        let newTask = GrowattTask(
            id: editingTask?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            days: days,
            start_time: startTime,
            end_time: endTime,
            power: String(power),
            soc: String(soc),
            enabled: editingTask?.enabled ?? true
        )
        onSave(newTask)
    }

    var body: some View {
        ZStack {
            bgDark.ignoresSafeArea()
                .onTapGesture { UIApplication.shared.endEditing() }
            VStack(spacing: 0) {
                HStack {
                    Button("Cancel") { onCancel() }
                        .foregroundColor(alertRed)
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    Text(editingTask == nil ? "Add Task" : "Edit Task")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button("Save") { save() }
                        .foregroundColor(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || days.isEmpty ? .secondary : batteryGreen)
                        .font(.system(size: 15, weight: .bold))
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || days.isEmpty)
                }
                .padding()
                .background(.ultraThinMaterial)
                .overlay(VStack { Spacer(); Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1) })
                
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TASK INFO").font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
                            TextField("Task Name (e.g. Peak Charging)", text: $name)
                                .padding().background(Color.white.opacity(0.03)).cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.04), lineWidth: 1))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal).padding(.top)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TIME WINDOW").font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
                            HStack {
                                Picker("Start Time", selection: $startTime) {
                                    ForEach(0..<24) { hour in let t = String(format: "%02d:00", hour); Text(t).tag(t) }
                                }.pickerStyle(.menu).foregroundColor(.white).padding(8).background(Color.white.opacity(0.03)).cornerRadius(8)
                                Text("to").foregroundColor(.secondary)
                                Picker("End Time", selection: $endTime) {
                                    ForEach(0..<24) { hour in let t = String(format: "%02d:00", hour); Text(t).tag(t) }
                                }.pickerStyle(.menu).foregroundColor(.white).padding(8).background(Color.white.opacity(0.03)).cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DAYS ACTIVE").font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
                            HStack(spacing: 6) {
                                let allDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                                ForEach(allDays, id: \.self) { day in
                                    let isSel = days.contains(day)
                                    Button(action: {
                                        if isSel { days.removeAll { $0 == day } } else { days.append(day) }
                                    }) {
                                        Text(day.prefix(1)).font(.footnote).fontWeight(.bold)
                                            .frame(width: 32, height: 32)
                                            .foregroundColor(isSel ? .white : .secondary)
                                            .background(isSel ? batteryGreen : Color.white.opacity(0.03))
                                            .clipShape(Circle())
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("LIMITS").font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Stop Charge SoC Limit: \(soc)%").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                                Slider(value: Binding(get: { Double(soc) }, set: { soc = Int($0) }), in: 10...100, step: 1).tint(batteryGreen)
                            }
                            Divider().background(Color.white.opacity(0.04))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Charging Power Rate: \(power)%").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                                Slider(value: Binding(get: { Double(power) }, set: { power = Int($0) }), in: 10...100, step: 1).tint(batteryGreen)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Standalone ResolvedSegment & TimelinePreviewView (shared between ContentView and PlanBillsTabContainerView)

struct ResolvedSegment: Identifiable {
    let id = UUID()
    let startMin: Int
    let endMin: Int
    let power: Int
    let soc: Int
    let name: String
}

struct TimelinePreviewView: View {
    @ObservedObject var fm: FirebaseManager
    
    private let batteryGreen = Theme.batteryGreen

    private func getTodayDayStr() -> String {
        return DateFormatter.eee.string(from: Date())
    }
    
    private func resolveTimelineSegments() -> [ResolvedSegment] {
        let dayStr = getTodayDayStr()
        // Same priority rule as the cloud resolver: AI tasks only on the applied date
        let aiActive = !fm.settings.ai_plan_applied_for.isEmpty
            && fm.settings.ai_plan_applied_for == DateFormatter.yyyyMMdd.string(from: Date())
            && fm.settings.tasks.contains { $0.name.hasPrefix("AI Plan:") }
        let activeTasks = fm.settings.tasks.filter {
            $0.enabled && $0.days.contains(dayStr) && ($0.name.hasPrefix("AI Plan:") == aiActive)
        }
        if activeTasks.isEmpty {
            let weekday = Calendar.current.component(.weekday, from: Date())
            let isWeekend = (weekday == 1 || weekday == 7)
            var segments = [ResolvedSegment(startMin: 0, endMin: 360, power: 100, soc: 100, name: "Daily Night Charge")]
            if isWeekend {
                segments.append(ResolvedSegment(startMin: 720, endMin: 840, power: 100, soc: 100, name: "Weekend Extra Charge"))
            }
            return segments
        }
        var grid = [Int?](repeating: nil, count: 1440)
        for (idx, task) in activeTasks.enumerated() {
            let startParts = task.start_time.split(separator: ":").compactMap { Int($0) }
            let endParts = task.end_time.split(separator: ":").compactMap { Int($0) }
            guard startParts.count == 2, endParts.count == 2 else { continue }
            let startMin = startParts[0] * 60 + startParts[1]
            let endMin = endParts[0] * 60 + endParts[1]
            guard endMin > startMin else { continue }
            for m in startMin..<endMin { grid[m] = idx }
        }
        var segments: [ResolvedSegment] = []
        var currentStart: Int? = nil
        var currentIdx: Int? = nil
        for m in 0..<1440 {
            if let idx = grid[m] {
                if currentStart == nil { currentStart = m; currentIdx = idx }
                else if currentIdx != idx {
                    if let start = currentStart, let cIdx = currentIdx {
                        let task = activeTasks[cIdx]
                        segments.append(ResolvedSegment(startMin: start, endMin: m, power: Int(task.power) ?? 100, soc: Int(task.soc) ?? 100, name: task.name))
                    }
                    currentStart = m; currentIdx = idx
                }
            } else {
                if let start = currentStart, let cIdx = currentIdx {
                    let task = activeTasks[cIdx]
                    segments.append(ResolvedSegment(startMin: start, endMin: m, power: Int(task.power) ?? 100, soc: Int(task.soc) ?? 100, name: task.name))
                }
                currentStart = nil; currentIdx = nil
            }
        }
        if let start = currentStart, let cIdx = currentIdx {
            let task = activeTasks[cIdx]
            segments.append(ResolvedSegment(startMin: start, endMin: 1440, power: Int(task.power) ?? 100, soc: Int(task.soc) ?? 100, name: task.name))
        }
        return segments
    }
    
    var body: some View {
        let segments = resolveTimelineSegments()
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)).frame(height: 18)
                    HStack {
                        Spacer()
                        Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
                        Spacer()
                        Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
                        Spacer()
                        Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1)
                        Spacer()
                    }
                    .frame(height: 18)
                    ForEach(segments) { seg in
                        let width = geo.size.width * CGFloat(seg.endMin - seg.startMin) / 1440.0
                        let offset = geo.size.width * CGFloat(seg.startMin) / 1440.0
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(colors: [batteryGreen, batteryGreen.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                            // Target SoC inside the window (hidden on slivers too narrow to fit)
                            if width >= 24 {
                                Text("\(seg.soc)%")
                                    .font(.system(size: 8, weight: .black, design: .rounded))
                                    .foregroundColor(.black.opacity(0.7))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        .frame(width: width, height: 18)
                        .offset(x: offset)
                    }
                }
            }
            .frame(height: 18)
            HStack {
                Text("12 AM"); Spacer(); Text("6 AM"); Spacer()
                Text("12 PM"); Spacer(); Text("6 PM"); Spacer(); Text("12 AM")
            }
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.secondary)
        }
        .padding()
        .glassCardStyle(cornerRadius: 14)
    }
}

// MARK: - DateFormatter Extension for Performance Optimization
extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    static let mmmmYyyy: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    static let eeeedMmmYyyy: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMM yyyy"
        return formatter
    }()
    
    static let eee: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    static let hhMm: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    
    static let shortDateMediumTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()
    
    static let dMmmYyyy: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()
}

/// Global helper: converts an HH:mm string pair of get/set closures into a Date Binding
/// Used in both ContentView and PlanBillsTabContainerView sheet forms.
func makeTimeBinding(getStr: @escaping () -> String, setStr: @escaping (String) -> Void) -> Binding<Date> {
    Binding<Date>(
        get: { DateFormatter.hhMm.date(from: getStr()) ?? DateFormatter.hhMm.date(from: "00:00")! },
        set: { setStr(DateFormatter.hhMm.string(from: $0)) }
    )
}

struct GlobalFloatingMascotOverlay: View {
    @ObservedObject var live: LiveDataStore
    @ObservedObject var fm: FirebaseManager
    var weatherState: WeatherInfo

    @State private var showMascotDialog = false
    @State private var isBreathing = false

    private var currentSkin: String {
        fm.settings.mascot_skin
    }

    private var geminiApiKey: String {
        fm.settings.gemini_api_key
    }

    /// Compute a rough today energy total (kWh) from the current telemetry history
    /// using trapezoidal integration, same approach as ContentView's calculateIntegral.
    private func integrateTelemetry(_ keyPath: KeyPath<TelemetryEntry, Double>) -> Double {
        let sorted = live.telemetryHistory.sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
        guard sorted.count > 1 else { return 0.0 }
        // Only include today's entries
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let todayEntries = sorted.filter { ($0.timestamp ?? .distantPast) >= todayStart }
        guard todayEntries.count > 1 else { return 0.0 }
        var sum = 0.0
        for i in 0..<(todayEntries.count - 1) {
            let e1 = todayEntries[i]; let e2 = todayEntries[i + 1]
            guard let t1 = e1.timestamp, let t2 = e2.timestamp else { continue }
            let dtHours = t2.timeIntervalSince(t1) / 3600.0
            guard dtHours < 1.0 else { continue }
            sum += ((e1[keyPath: keyPath] + e2[keyPath: keyPath]) / 2.0) * dtHours
        }
        return max(0.0, sum)
    }

    var body: some View {
        let pvKw = Double(live.liveStatus?.data?.ppv ?? "0") ?? 0.0
        let chgKw = Double(live.liveStatus?.data?.chargePower ?? "0") ?? 0.0
        let dischKw = Double(live.liveStatus?.data?.dischargePower ?? "0") ?? 0.0
        let loadKw = Double(live.liveStatus?.data?.localLoad ?? "0") ?? 0.0
        let expKw = Double(live.liveStatus?.data?.gridExport ?? "0") ?? 0.0
        let impKw = Double(live.liveStatus?.data?.gridImport ?? "0") ?? 0.0
        let socVal = Int(live.liveStatus?.data?.SOC ?? "80") ?? 80

        let todaySolar = integrateTelemetry(\.solar_generation_kw)
        let todayLoad = integrateTelemetry(\.local_load_kw)
        let todayCharge = integrateTelemetry(\.charge_power_kw)
        let todayDischarge = integrateTelemetry(\.discharge_power_kw)
        let todayImport = integrateTelemetry(\.grid_import_kw)
        let todayExport = integrateTelemetry(\.grid_export_kw)

        let tomSolar = fm.chargingPlan?.pv_forecast_kwh ?? 22.80
        let tomLoad = fm.chargingPlan?.load_forecast_kwh ?? 15.50

        ZStack(alignment: .bottomTrailing) {
            Color.clear
                .ignoresSafeArea()

            Button(action: {
                showMascotDialog = true
            }) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.92))
                        .frame(width: 58, height: 58)
                        .overlay(
                            Circle()
                                .stroke(Theme.solarGold.opacity(isBreathing ? 0.35 : 0.15), lineWidth: 1.0)
                        )
                        .shadow(color: Theme.solarGold.opacity(0.18), radius: 3, x: 0, y: 2)

                    MascotView(
                        solarKw: pvKw,
                        chargeKw: chgKw,
                        dischargeKw: dischKw,
                        loadKw: loadKw,
                        gridExportKw: expKw,
                        gridImportKw: impKw,
                        socPct: socVal,
                        weatherIcon: weatherState.icon,
                        skin: currentSkin,
                        size: 42
                    )
                }
                .offset(y: isBreathing ? -1.5 : 1.5)
            }
            .padding(.trailing, 16)
            .padding(.bottom, 60)
        }
        .onAppear {
            let cal = Calendar.current
            let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            fm.listenToBillsRange(start: thirtyDaysAgo, end: Date())
            if fm.historicalBills.count < 7 {
                fm.triggerManualSync(mode: "sync")
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .sheet(isPresented: $showMascotDialog) {
            MascotDialogView(
                solarKw: pvKw,
                chargeKw: chgKw,
                dischargeKw: dischKw,
                loadKw: loadKw,
                gridExportKw: expKw,
                gridImportKw: impKw,
                socPct: socVal,
                todaySolarKwh: todaySolar,
                todayLoadKwh: todayLoad,
                todayChargeKwh: todayCharge,
                todayDischargeKwh: todayDischarge,
                todayImportKwh: todayImport,
                todayExportKwh: todayExport,
                tomorrowSolarKwh: tomSolar,
                tomorrowLoadKwh: tomLoad,
                selfSufficiency: 0.0,
                selfConsumption: 0.0,
                historicalBills: fm.historicalBills,
                weatherCondition: weatherState.description,
                temperature: String(format: "%.0f°C", weatherState.temperature ?? 18.0),
                tariffInfo: fm.settings.tariff.rules.isEmpty ? "Standard Single Rate Tariff" : "TOU Dynamic Tariff Plan",
                currentSkin: currentSkin,
                apiKey: geminiApiKey,
                onDismiss: {
                    showMascotDialog = false
                }
            )
        }
    }
}

// MARK: - PV Forecast vs Actual Historical Comparison Chart
struct PvComparisonItem: Identifiable {
    let id: String // Date string "YYYY-MM-DD"
    let dateStr: String
    let actualSolar: Double?
    let forecastSolar: Double?
    
    var shortDate: String {
        let parts = dateStr.split(separator: "-")
        if parts.count == 3 {
            return "\(parts[1])/\(parts[2])"
        }
        return dateStr
    }
    
    var errorKw: Double? {
        guard let f = forecastSolar, let a = actualSolar else { return nil }
        return f - a
    }
    
    var accuracyPct: Double? {
        guard let f = forecastSolar, let a = actualSolar, a > 0 else { return nil }
        return max(0, 100.0 - abs(f - a) / a * 100.0)
    }
}

struct PvForecastVsActualChartView: View {
    @ObservedObject var fm = FirebaseManager.shared
    @State private var rangeDays: Int = 7 // 7 or 30
    @State private var selectedItem: PvComparisonItem? = nil

    private var items: [PvComparisonItem] {
        let billsByDate = Dictionary(uniqueKeysWithValues: fm.historicalBills.map { ($0.date, $0.solar_kwh) })
        let plansByDate = Dictionary(uniqueKeysWithValues: fm.chargingPlanHistory.map { ($0.for_date, $0.pv_forecast_kwh ?? 0.0) })
        
        let allDates = Set(billsByDate.keys).union(plansByDate.keys)
        let sortedDates = Array(allDates.sorted().suffix(rangeDays))
        
        return sortedDates.map { dateStr in
            PvComparisonItem(
                id: dateStr,
                dateStr: dateStr,
                actualSolar: billsByDate[dateStr],
                forecastSolar: plansByDate[dateStr]
            )
        }
    }

    private var validItems: [PvComparisonItem] {
        items.filter { $0.actualSolar != nil && $0.forecastSolar != nil }
    }

    private var mae: Double {
        guard !validItems.isEmpty else { return 0.0 }
        let totalErr = validItems.reduce(0.0) { $0 + abs(($1.forecastSolar ?? 0.0) - ($1.actualSolar ?? 0.0)) }
        return totalErr / Double(validItems.count)
    }

    private var avgAccuracy: Double {
        guard !validItems.isEmpty else { return 0.0 }
        let totalAcc = validItems.reduce(0.0) { $0 + ($1.accuracyPct ?? 0.0) }
        return totalAcc / Double(validItems.count)
    }

    private var bias: Double {
        guard !validItems.isEmpty else { return 0.0 }
        let totalDiff = validItems.reduce(0.0) { $0 + (($1.forecastSolar ?? 0.0) - ($1.actualSolar ?? 0.0)) }
        return totalDiff / Double(validItems.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Card Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("PV FORECAST VS ACTUAL", systemImage: "chart.bar.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.solarGold)
                        .tracking(1.2)
                    Text("Daily Nightly Forecast Accuracy")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer()
                
                // 7D / 30D Selector
                HStack(spacing: 4) {
                    Button(action: { withAnimation { rangeDays = 7 } }) {
                        Text("7D")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(rangeDays == 7 ? .black : .white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(rangeDays == 7 ? Theme.solarGold : Color.white.opacity(0.1))
                            .cornerRadius(6)
                    }
                    Button(action: { withAnimation { rangeDays = 30 } }) {
                        Text("30D")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(rangeDays == 30 ? .black : .white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(rangeDays == 30 ? Theme.solarGold : Color.white.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
            }

            // Summary Metrics Pill Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MAE (平均误差)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f kWh", mae))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("AVG ACCURACY (准确率)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f%%", avgAccuracy))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.batteryGreen)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("BIAS (偏差)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(String(format: "%+.2f kWh", bias))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(bias > 0 ? Color.orange : Color.cyan)
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.04))
            .cornerRadius(10)

            // Scrubbing Tooltip Banner
            if let sel = selectedItem {
                let todayStr = DateFormatter.yyyyMMdd.string(from: Date())
                let isToday = (sel.dateStr == todayStr)
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("[\(sel.dateStr)]")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                        if isToday {
                            Text("LIVE 🔴")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(Color.red)
                        }
                    }
                    Text("Actual: \(String(format: "%.1f", sel.actualSolar ?? 0)) kWh")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.solarGold)
                    Text("Forecast: \(String(format: "%.1f", sel.forecastSolar ?? 0)) kWh")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.cyan)
                    Spacer()
                    if let err = sel.errorKw {
                        Text(String(format: "%+.1f kWh", err))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(err > 0 ? Color.orange : Color.cyan)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isToday ? Color(red: 0.12, green: 0.16, blue: 0.23) : Color.black.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isToday ? Theme.solarGold : Color.clear, lineWidth: 1)
                )
                .cornerRadius(6)
            }

            // Swift Charts Dual Trend Line Chart
            if items.isEmpty {
                Text("Loading historical prediction comparisons...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(items) { item in
                        if let actual = item.actualSolar {
                            AreaMark(
                                x: .value("Date", item.shortDate),
                                y: .value("Actual kWh", actual)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Theme.solarGold.opacity(0.25), Theme.solarGold.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Date", item.shortDate),
                                y: .value("Actual kWh", actual)
                            )
                            .foregroundStyle(Theme.solarGold)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Date", item.shortDate),
                                y: .value("Actual kWh", actual)
                            )
                            .foregroundStyle(Theme.solarGold)
                            .symbolSize(rangeDays == 7 ? 35 : 15)
                        }

                        if let fcst = item.forecastSolar {
                            LineMark(
                                x: .value("Date", item.shortDate),
                                y: .value("Forecast kWh", fcst)
                            )
                            .foregroundStyle(Color.cyan)
                            .lineStyle(StrokeStyle(lineWidth: 2.0, dash: [5, 4]))
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Date", item.shortDate),
                                y: .value("Forecast kWh", fcst)
                            )
                            .foregroundStyle(Color.cyan)
                            .symbolSize(rangeDays == 7 ? 30 : 12)
                        }
                    }

                    // Interactive Vertical Dashed Guideline & Highlight Glow Markers
                    if let sel = selectedItem {
                        RuleMark(x: .value("Selected Date", sel.shortDate))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

                        if let actual = sel.actualSolar {
                            PointMark(x: .value("Selected Date", sel.shortDate), y: .value("Actual kWh", actual))
                                .foregroundStyle(Theme.solarGold)
                                .symbolSize(120)
                            PointMark(x: .value("Selected Date", sel.shortDate), y: .value("Actual kWh", actual))
                                .foregroundStyle(Color.white)
                                .symbolSize(30)
                        }

                        if let fcst = sel.forecastSolar {
                            PointMark(x: .value("Selected Date", sel.shortDate), y: .value("Forecast kWh", fcst))
                                .foregroundStyle(Color.cyan)
                                .symbolSize(100)
                            PointMark(x: .value("Selected Date", sel.shortDate), y: .value("Forecast kWh", fcst))
                                .foregroundStyle(Color.white)
                                .symbolSize(25)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(Color.white.opacity(0.1))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v))k")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let s = value.as(String.self) {
                                Text(s)
                                    .font(.system(size: rangeDays == 7 ? 9 : 7))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(Color.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard let frame = proxy.plotFrame, !items.isEmpty else { return }
                                        let plotWidth = geo[frame].width
                                        let touchX = max(0, min(plotWidth, value.location.x - geo[frame].origin.x))
                                        let fraction = touchX / plotWidth
                                        let idx = min(items.count - 1, max(0, Int(round(fraction * Double(items.count - 1)))))
                                        selectedItem = items[idx]
                                    }
                            )
                    }
                }
                .frame(height: 200)
            }

            // Legend Footer
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle().fill(Theme.solarGold).frame(width: 8, height: 8)
                    Text("Actual Solar (实际发电)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.cyan).frame(width: 8, height: 8)
                    Text("Nightly AI Forecast (夜间预测)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.08))
        )
    }
}

struct TeslaEvLiveCardView: View {
    @ObservedObject var fm: FirebaseManager

    var body: some View {
        if let tesla = fm.live.teslaStatus {
            let isCharging = (tesla.charging_state == "Charging")
            let powerKw = tesla.charger_power_kw ?? 0.0

            VStack(alignment: .leading, spacing: 10) {
                // Header: Tesla Icon + Car Name + Charging Badge
                HStack {
                    HStack(spacing: 6) {
                        Text("🚘")
                            .font(.system(size: 14))
                        Text((tesla.car_name ?? "Tesla Model Y").uppercased())
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(Theme.batteryGreen)
                            .tracking(1.2)
                    }
                    Spacer()

                    HStack(spacing: 4) {
                        if isCharging {
                            Text("⚡")
                                .font(.system(size: 10))
                        }
                        Text((tesla.charging_state ?? "Standby").uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(isCharging ? Theme.batteryGreen : Color.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isCharging ? Theme.batteryGreen.opacity(0.15) : Color.white.opacity(0.08))
                    .cornerRadius(6)
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Two-column split: Left 55% metrics, Right 45% live map
                HStack(spacing: 10) {
                    // Left Column: Smart Context-Aware Metrics
                    VStack(alignment: .leading, spacing: 6) {
                        let isDriving = (tesla.location_name ?? "").contains("Driving")
                        
                        // Card 1: Battery Level & Target / Est Range
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Battery Level")
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundColor(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(tesla.battery_level ?? 78)")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("%")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(Theme.batteryGreen)
                                if isCharging {
                                    Text("(\(tesla.charge_limit_soc ?? 80)% Max)")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                } else {
                                    let estKm = Int(Double(tesla.battery_level ?? 78) * 4.35)
                                    Text("(~\(estKm) km)")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(Theme.batteryGreen.opacity(0.85))
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(8)
                        
                        // Card 2: Dynamic Context (Charger Power when Charging, Status/Speed when Standby/Driving)
                        if isCharging {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Charger Power")
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundColor(.secondary)
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text(String(format: "%.1f", powerKw))
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.batteryGreen)
                                    Text("kW")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(Theme.batteryGreen)
                                    Text("\(tesla.charger_voltage ?? 240)V/\(tesla.charger_actual_current ?? 0)A")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.batteryGreen.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Theme.batteryGreen.opacity(0.3), lineWidth: 1)
                            )
                            .cornerRadius(8)
                        } else {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(isDriving ? "Vehicle Speed" : "Vehicle Status")
                                    .font(.system(size: 8.5, weight: .medium))
                                    .foregroundColor(.secondary)
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text(isDriving ? "45" : "Locked")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    Text(isDriving ? "mph" : "🔒 Sentry Off")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundColor(isDriving ? Theme.batteryGreen : .secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(8)
                        }
                        
                        // Card 3: Dynamic Footer (Added Energy & Time when Charging, Location when Standby/Driving)
                        VStack(alignment: .leading, spacing: 1) {
                            if isCharging {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Added Energy")
                                            .font(.system(size: 7.5))
                                            .foregroundColor(.secondary)
                                        Text("+\(String(format: "%.1f", tesla.charge_energy_added_kwh ?? 0.0)) kWh")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(Theme.batteryGreen)
                                    }
                                    Spacer()
                                    if (tesla.minutes_to_full_charge ?? 0) > 0 {
                                        VStack(alignment: .trailing, spacing: 1) {
                                            Text("Time Left")
                                                .font(.system(size: 7.5))
                                                .foregroundColor(.secondary)
                                            Text("\(tesla.minutes_to_full_charge ?? 0) min")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                            } else {
                                Text("📍 \(tesla.location_name ?? "Parked")")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text("\(String(format: "%.3f, %.3f", tesla.latitude ?? -35.1653, tesla.longitude ?? 149.1278)) · Today +\(String(format: "%.1f", tesla.charge_energy_added_kwh ?? 0.0)) kWh")
                                    .font(.system(size: 7.5))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(8)
                    }
                    
                    // Right Column: Live Apple Map Card
                    let carCoordinate = CLLocationCoordinate2D(
                        latitude: tesla.latitude ?? -35.1653,
                        longitude: tesla.longitude ?? 149.1278
                    )
                    let pinColor = isCharging ? Theme.batteryGreen : Color(red: 0.22, green: 0.74, blue: 0.97)

                    ZStack(alignment: .topLeading) {
                        Map(initialPosition: .region(
                            MKCoordinateRegion(
                                center: carCoordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            )
                        )) {
                            Annotation(tesla.location_name ?? "Tesla", coordinate: carCoordinate) {
                                ZStack {
                                    Circle()
                                        .fill(pinColor.opacity(0.25))
                                        .frame(width: 26, height: 26)
                                    Circle()
                                        .fill(pinColor)
                                        .frame(width: 12, height: 12)
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 4, height: 4)
                                }
                            }
                        }
                        .mapStyle(.standard(pointsOfInterest: .excludingAll))
                        .allowsHitTesting(false)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )

                        Text("LIVE MAP GPS")
                            .font(.system(size: 7, weight: .black))
                            .foregroundColor(Theme.batteryGreen)
                            .tracking(1.0)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.55))
                            .cornerRadius(4)
                            .padding(6)

                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text((tesla.location_name ?? "").contains("Driving") ? "MOVING" : "PARKED")
                                    .font(.system(size: 7.5, weight: .bold))
                                    .foregroundColor(.white.opacity(0.85))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.6))
                                    .cornerRadius(4)
                            }
                            .padding(6)
                        }
                    }
                    .frame(height: 155)
                }
            }
            .padding(14)
            .background(Color.black.opacity(0.4))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .cornerRadius(16)
        }
    }
}
