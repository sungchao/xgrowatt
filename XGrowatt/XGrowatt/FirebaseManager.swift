import Foundation
import Combine
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

struct GrowattTask: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String = ""
    var days: [String] = [] // e.g. ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    var start_time: String = "00:00"
    var end_time: String = "06:00"
    var power: String = "100"
    var soc: String = "100"
    var enabled: Bool = true
}

struct TariffRule: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String = ""
    var days: [String] = [] // e.g. ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    var start_time: String = "00:00"
    var end_time: String = "06:00"
    var import_rate: Double = 0.30       // $/kWh
    var export_rate: Double = 0.08       // $/kWh
    var enabled: Bool = true
}

struct ElectricityTariffPlan: Codable, Equatable {
    var dailySupplyCharge: Double = 0.95 // $/day
    var fallbackImportRate: Double = 0.30 // $/kWh
    var fallbackExportRate: Double = 0.08 // $/kWh
    var rules: [TariffRule] = []
}

struct DailyBill: Identifiable, Codable {
    var id: String { date }
    var date: String
    var timestamp: Date
    var solar_kwh: Double
    var load_kwh: Double
    var import_kwh: Double
    var export_kwh: Double
    var charge_kwh: Double
    var discharge_kwh: Double
    var net_cost: Double
    var savings: Double
    var arbitrage: Double
    var daily_supply_charge: Double
    var import_cost: Double? = 0.0
    var export_credit: Double? = 0.0
    
    var peak_kwh: Double? = 0.0
    var peak_cost: Double? = 0.0
    var off_peak_kwh: Double? = 0.0
    var off_peak_cost: Double? = 0.0
    var free_kwh: Double? = 0.0
    var free_cost: Double? = 0.0
    var tesla_kwh: Double? = 0.0
    var house_load_kwh: Double? = 0.0
    var tesla_cost: Double? = 0.0
    var tesla_savings: Double? = 0.0
}

struct GrowattSettings: Codable {
    var username: String = ""
    var password: String = ""
    var device_sn: String = ""
    var timezone: String = "Australia/Canberra"
    var server_url: String = "https://openapi-au.growatt.com/"
    var api_token: String = ""
    
    var latitude: Double? = nil
    var longitude: Double? = nil
    
    var tasks: [GrowattTask] = []
    var tariff: ElectricityTariffPlan = ElectricityTariffPlan()

    // Which date the applied AI Plan targets ("" = none). The cloud resolver gives AI
    // tasks PRIORITY on exactly this date and ignores them on any other — manual weekly
    // tasks are never modified, so the weekly plan resumes by itself the day after.
    var ai_plan_applied_for: String = ""
    // AUTO mode: the nightly 23:30 generation also applies its plan automatically.
    // Safety-gated server-side: no fresh forecast -> no generation -> weekly plan runs.
    var ai_auto_apply: Bool = false

    var gemini_api_key: String = ""
    var mascot_skin: String = "slime"

    enum CodingKeys: String, CodingKey {
        case username, password, device_sn, timezone, server_url, api_token, latitude, longitude, tasks, tariff
        case ai_plan_applied_for, ai_auto_apply
        case gemini_api_key, mascot_skin
    }
    
    init(username: String = "", password: String = "", device_sn: String = "") {
        self.username = username
        self.password = password
        self.device_sn = device_sn
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        device_sn = try container.decodeIfPresent(String.self, forKey: .device_sn) ?? ""
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone) ?? "Australia/Canberra"
        server_url = try container.decodeIfPresent(String.self, forKey: .server_url) ?? "https://openapi-au.growatt.com/"
        api_token = try container.decodeIfPresent(String.self, forKey: .api_token) ?? ""
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        tasks = try container.decodeIfPresent([GrowattTask].self, forKey: .tasks) ?? []
        tariff = try container.decodeIfPresent(ElectricityTariffPlan.self, forKey: .tariff) ?? ElectricityTariffPlan()
        ai_plan_applied_for = try container.decodeIfPresent(String.self, forKey: .ai_plan_applied_for) ?? ""
        ai_auto_apply = try container.decodeIfPresent(Bool.self, forKey: .ai_auto_apply) ?? false
        gemini_api_key = try container.decodeIfPresent(String.self, forKey: .gemini_api_key) ?? ""
        mascot_skin = try container.decodeIfPresent(String.self, forKey: .mascot_skin) ?? "slime"
    }
}

struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    var intValue: Int?
    init?(intValue: Int) {
        return nil
    }
}

struct GrowattStatus: Codable {
    var last_run: Date?
    var status: String = "unknown"
    var message: String = ""
    var applied_schedule: String?
    var params: [String]?
    var trigger: String = ""
    // Drift detection (refreshed every 5-min cycle): does the inverter's REPORTED charge
    // schedule match what we resolved? false = someone changed it via the Growatt app/API.
    var inverter_matches: Bool?
    var inverter_actual: String?
}

struct GrowattLiveStatus: Codable {
    var last_updated: Date?
    var device_sn: String = ""
    var plant_id: String = ""
    var data: LiveDataFields?
    
    struct LiveDataFields: Codable {
        var SOC: String?
        var ppv: String?
        var chargePower: String?
        var dischargePower: String?
        var localLoad: String?
        var gridExport: String?
        var gridImport: String?
        // Current work-mode priority: "0" load first, "1" battery first, "2" grid first
        var priorityChoose: String?
        // Per-MPPT string readings (nil when the payload doesn't provide them)
        var ppv1: String?
        var ppv2: String?
        var vpv1: String?
        var vpv2: String?
        // Per-string daily yield (kWh)
        var epv1Today: String?
        var epv2Today: String?
        var bmsDeltaVolt: String?
        var vBat: String?
        var cellVoltages: [Double]?
        var modeled_soc: String?
        var chargePowerCommand: String?
        var disChargePowerCommand: String?
        var uwMinTemprCell: String?
        var uwMaxTemprCell: String?
        var bmsBatteryTemp: String?
        
        init(SOC: String?, ppv: String?, chargePower: String?, dischargePower: String?, localLoad: String?, gridExport: String?, gridImport: String?) {
            self.SOC = SOC
            self.ppv = ppv
            self.chargePower = chargePower
            self.dischargePower = dischargePower
            self.localLoad = localLoad
            self.gridExport = gridExport
            self.gridImport = gridImport
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
            
            func decodeString(forKeys keys: [String]) -> String? {
                for keyStr in keys {
                    guard let key = DynamicCodingKeys(stringValue: keyStr) else { continue }
                    if let valInt = try? container.decode(Int.self, forKey: key) { return String(valInt) }
                    if let valDouble = try? container.decode(Double.self, forKey: key) { return String(valDouble) }
                    if let valStr = try? container.decode(String.self, forKey: key) { return valStr }
                }
                return nil
            }
            
            self.SOC = decodeString(forKeys: ["SOC", "soc", "bmsSOC"])
            self.ppv = decodeString(forKeys: ["ppv"])
            self.chargePower = decodeString(forKeys: ["chargePower", "pcharge1"])
            self.dischargePower = decodeString(forKeys: ["pdisCharge1", "pdischarge1"])
            self.localLoad = decodeString(forKeys: ["pLocalLoad", "pself", "pac"])
            self.gridExport = decodeString(forKeys: ["pactogrid", "pacToGridTotal", "pex"])
            self.gridImport = decodeString(forKeys: ["pactouser", "pacToUserTotal"])
            self.priorityChoose = decodeString(forKeys: ["priorityChoose"])
            self.ppv1 = decodeString(forKeys: ["ppv1", "pPv1", "pPV1"])
            self.ppv2 = decodeString(forKeys: ["ppv2", "pPv2", "pPV2"])
            self.vpv1 = decodeString(forKeys: ["vpv1", "vPv1"])
            self.vpv2 = decodeString(forKeys: ["vpv2", "vPv2"])
            self.epv1Today = decodeString(forKeys: ["epv1Today", "epv1today"])
            self.epv2Today = decodeString(forKeys: ["epv2Today", "epv2today"])
            self.bmsDeltaVolt = decodeString(forKeys: ["bmsDeltaVolt", "cell_delta_mv"])
            self.vBat = decodeString(forKeys: ["vBat", "vbat", "battery_voltage"])
            self.modeled_soc = decodeString(forKeys: ["modeled_soc", "modeledSOC"])
            self.chargePowerCommand = decodeString(forKeys: ["chargePowerCommand"])
            self.disChargePowerCommand = decodeString(forKeys: ["disChargePowerCommand", "dischargePowerCommand"])
            self.uwMinTemprCell = decodeString(forKeys: ["uwMinTemprCell"])
            self.uwMaxTemprCell = decodeString(forKeys: ["uwMaxTemprCell"])
            self.bmsBatteryTemp = decodeString(forKeys: ["bmsBatteryTemp", "batteryTemperature"])
            
            var cVolts: [Double] = []
            for i in 1...16 {
                if let vStr = decodeString(forKeys: ["bmsCell\(i)Volt", "bmsCell\(i)Voltage"]), let v = Double(vStr), v > 0 {
                    cVolts.append(v)
                }
            }
            if !cVolts.isEmpty {
                self.cellVoltages = cVolts
            }
        }
    }
}

struct SyncLog: Identifiable, Codable {
    var id: String?
    var timestamp: Date?
    var status: String = ""
    var message: String = ""
    var applied_schedule: String?
    var trigger: String = ""
    
    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case status
        case message
        case applied_schedule
        case trigger
    }
}

struct TelemetryEntry: Identifiable, Codable {
    var id: String?
    var timestamp: Date?
    var soc: Int = 0
    var modeled_soc: Double? = nil
    var battery_energy_kwh: Double = 0.0
    var battery_voltage: Double = 0.0
    var cell_delta_mv: Double? = nil
    var cell_voltages: [Double]? = nil
    var solar_generation_kw: Double = 0.0
    var charge_power_kw: Double = 0.0
    var discharge_power_kw: Double = 0.0
    var local_load_kw: Double = 0.0
    var grid_export_kw: Double = 0.0
    var grid_import_kw: Double = 0.0

    // Per-MPPT string readings (nil for entries recorded before this was added, or when
    // the inverter payload doesn't provide per-string data).
    var pv1_power_kw: Double? = nil
    var pv2_power_kw: Double? = nil
    var pv1_voltage: Double? = nil
    var pv2_voltage: Double? = nil

    // Weather snapshot joined in server-side at write time (nil for older entries recorded
    // before this was added, or if the weather fetch failed that cycle).
    var temperature_c: Double? = nil
    var cell_temp_c: Double? = nil
    var apparent_temperature_c: Double? = nil
    var relative_humidity_pct: Double? = nil
    var precipitation_mm: Double? = nil
    var weather_code: Int? = nil
    var is_day: Bool? = nil
    var cloud_cover_pct: Double? = nil
    var cloud_cover_low_pct: Double? = nil
    var cloud_cover_mid_pct: Double? = nil
    var cloud_cover_high_pct: Double? = nil
    var shortwave_radiation_wm2: Double? = nil
    var direct_radiation_wm2: Double? = nil
    var diffuse_radiation_wm2: Double? = nil
    var direct_normal_irradiance_wm2: Double? = nil
    var sunshine_duration_s: Double? = nil
    var uv_index: Double? = nil
    var visibility_m: Double? = nil
    var wind_speed_kmh: Double? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case soc
        case modeled_soc
        case battery_energy_kwh
        case battery_voltage
        case solar_generation_kw
        case charge_power_kw
        case discharge_power_kw
        case local_load_kw
        case grid_export_kw
        case grid_import_kw
        case pv1_power_kw
        case pv2_power_kw
        case pv1_voltage
        case pv2_voltage
        case temperature_c
        case cell_temp_c
        case apparent_temperature_c
        case relative_humidity_pct
        case precipitation_mm
        case weather_code
        case is_day
        case cloud_cover_pct
        case cloud_cover_low_pct
        case cloud_cover_mid_pct
        case cloud_cover_high_pct
        case shortwave_radiation_wm2
        case direct_radiation_wm2
        case diffuse_radiation_wm2
        case direct_normal_irradiance_wm2
        case sunshine_duration_s
        case uv_index
        case visibility_m
        case wind_speed_kmh
    }
}

// MARK: - Charging Plan (advisory, generated nightly by the generate_charging_plan Cloud Function)

struct ChargingPlanTask: Codable, Identifiable {
    var id: String { name + start_time + end_time }
    var name: String = ""
    var days: [String] = []
    var start_time: String = "00:00"
    var end_time: String = "06:00"
    var power: String = "100"
    var soc: String = "100"
}

struct ChargingPlan: Codable {
    var generated_at: Date? = nil
    var for_date: String = ""
    var timezone: String? = nil
    var soc_now: Double? = nil
    var battery_rated_kwh: Double? = nil
    var target_soc: Int = 0
    var charge_kwh: Double = 0.0
    var est_cost: Double = 0.0
    // Whole-day bill estimate (same accounting as daily_bills; nil on plans generated
    // before this field existed)
    var est_day_cost: Double? = nil
    var offpeak_rate: Double? = nil
    var pv_forecast_kwh: Double? = nil
    var pv_forecast_raw_kwh: Double? = nil
    var load_forecast_kwh: Double? = nil
    var model_used: String? = nil
    var suggested_tasks: [ChargingPlanTask] = []
    var reasoning: [String] = []
    var mode: String? = nil
    var ev_sponge_active: Bool? = nil
    var ev_transfer_kwh: Double? = nil
    var tesla_continue_charge: Bool? = nil
    var ai_briefing: String? = nil
    var llm_plan_source: String? = nil
    var llm_target_delta: Int? = nil
    var llm_adjustment_reason: String? = nil
}

// MARK: - Weather Forecast (latest snapshot from the weather_forecast collection)

struct ForecastHour: Identifiable {
    var id: Date { time }
    var time: Date
    var gti: Double?          // plane-of-array irradiance W/m2 — the "solar fuel"
    var tempC: Double?
    var precipMm: Double?
    var cloudPct: Double?
    var weatherCode: Int?
    var isDay: Bool
}

struct TeslaStatus: Codable {
    var is_connected: Bool? = false
    var car_name: String? = "Tesla Model Y"
    var vehicle_state: String? = "online"
    var battery_level: Int? = 59
    var charge_limit_soc: Int? = 80
    var charger_power_kw: Double? = 0.0
    var charge_energy_added_kwh: Double? = 14.5
    var charging_state: String? = "Standby"
    var minutes_to_full_charge: Int? = 0
    var charger_voltage: Int? = 240
    var charger_actual_current: Int? = 0
    var latitude: Double? = -33.8688
    var longitude: Double? = 151.2093
    var location_name: String? = "Parked at Home"
    var last_updated: String? = ""
    var note: String? = ""
}

// MARK: - LiveDataStore
// Holds all the fast-changing / high-volume telemetry-adjacent state (live inverter status,
// sync logs, 300-entry telemetry history, sync-in-progress flag) in its OWN ObservableObject.
// Views that don't care about this data (e.g. Plan & Bills) should NOT hold a reference to it,
// so that its frequent Firestore updates don't force those views to re-render.
class LiveDataStore: ObservableObject {
    @Published var status: GrowattStatus?
    @Published var liveStatus: GrowattLiveStatus?
    @Published var teslaStatus: TeslaStatus? = TeslaStatus()
    @Published var logs: [SyncLog] = []
    @Published var telemetryHistory: [TelemetryEntry] = []
    @Published var isSyncing = false
    // Mirrored from status/growatt_inverter_settings (refreshed every sync cycle):
    // the inverter's charge stop SoC (battery-first target), load-first discharge floor,
    // and the charge/discharge power limits in kW (command % x pmax).
    @Published var chargeStopSoc: String?
    @Published var dischargeStopSoc: String?
    @Published var chargePowerKw: String?
    @Published var dischargePowerKw: String?
}

class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()

    private let db = Firestore.firestore()

    // Fast-changing live telemetry data lives in its own ObservableObject so that views which
    // only need `settings` / `historicalBills` (e.g. Plan & Bills) aren't re-rendered every time
    // live status / logs / telemetry update.
    let live = LiveDataStore()

    @Published var settings = GrowattSettings()
    @Published var historicalBills: [DailyBill] = []
    // Nightly advisory plan (status/charging_plan). Updates ~once a day, so it lives on the
    // slow-changing manager rather than LiveDataStore.
    @Published var chargingPlan: ChargingPlan?
    @Published var chargingPlanHistory: [ChargingPlan] = []
    @Published var isRegeneratingPlan = false
    @Published var isRefreshingTesla = false
    // Latest weather forecast snapshot (refreshed 3x daily + on every plan generation)
    @Published var forecastHours: [ForecastHour] = []
    @Published var forecastIssuedAt: Date?
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    
    private var settingsListener: ListenerRegistration?
    private var statusListener: ListenerRegistration?
    private var liveStatusListener: ListenerRegistration?
    private var teslaLiveListener: ListenerRegistration?
    private var logsListener: ListenerRegistration?
    private var telemetryListener: ListenerRegistration?
    private var billsListener: ListenerRegistration?
    private var chargingPlanListener: ListenerRegistration?
    private var chargingPlanHistoryListener: ListenerRegistration?
    private var inverterSettingsListener: ListenerRegistration?
    private var forecastListener: ListenerRegistration?
    
    init() {
        loadLocalCache()
        let useDemo = UserDefaults.standard.bool(forKey: "useDemoMode")
        if useDemo {
            self.settings = GrowattSettings(username: "demo@xgrowatt.com", password: "demopassword", device_sn: "DEMO_SPH_INVERTER_SN")
            self.isAuthenticated = true
            self.loadMockData()
        } else {
            authenticateAndListen()
        }
    }

    private func saveTelemetryCache(_ entries: [TelemetryEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: "cache_telemetry_history")
        }
    }

    private func saveBillsCache(_ bills: [DailyBill]) {
        if let data = try? JSONEncoder().encode(bills) {
            UserDefaults.standard.set(data, forKey: "cache_historical_bills")
        }
    }

    private func loadLocalCache() {
        if let teleData = UserDefaults.standard.data(forKey: "cache_telemetry_history"),
           let entries = try? JSONDecoder().decode([TelemetryEntry].self, from: teleData) {
            self.live.telemetryHistory = entries
        }
        if let billsData = UserDefaults.standard.data(forKey: "cache_historical_bills"),
           let bills = try? JSONDecoder().decode([DailyBill].self, from: billsData) {
            self.historicalBills = bills
        }
    }
    
    deinit {
        settingsListener?.remove()
        statusListener?.remove()
        liveStatusListener?.remove()
        teslaLiveListener?.remove()
        logsListener?.remove()
        telemetryListener?.remove()
        billsListener?.remove()
        chargingPlanListener?.remove()
        inverterSettingsListener?.remove()
        forecastListener?.remove()
    }
    
    func authenticateAndListen() {
        // Authenticate anonymously so we satisfy our Firestore security rules securely
        Auth.auth().signInAnonymously { [weak self] authResult, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Auth Error: \(error.localizedDescription)"
                    self.isAuthenticated = false
                }
                print("Firebase Auth Error: \(error)")
                return
            }
            
            DispatchQueue.main.async {
                self.isAuthenticated = true
                self.errorMessage = nil
                self.startListeners()
            }
        }
    }
    
    private func startListeners() {
        if settings.username == "demo@xgrowatt.com" {
            loadMockData()
            return
        }
        // 1. Listen to settings document
        settingsListener = db.collection("settings").document("growatt")
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("Error listening to settings: \(error)")
                    return
                }
                
                if let document = documentSnapshot, document.exists {
                    do {
                        let decodedSettings = try document.data(as: GrowattSettings.self)
                        DispatchQueue.main.async {
                            self.settings = decodedSettings
                        }
                    } catch {
                        print("Error decoding settings: \(error)")
                    }
                } else {
                    // Document doesn't exist, we will use default initialized struct
                    self.saveSettings(self.settings)
                }
            }
            
        // 2. Listen to status document
        statusListener = db.collection("status").document("growatt")
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("Error listening to status: \(error)")
                    return
                }
                
                if let document = documentSnapshot, document.exists {
                    do {
                        let decodedStatus = try document.data(as: GrowattStatus.self)
                        DispatchQueue.main.async {
                            self.live.status = decodedStatus
                        }
                    } catch {
                        print("Error decoding status: \(error)")
                    }
                }
            }

        // 3. Listen to liveStatus document
        liveStatusListener = db.collection("status").document("growatt_live")
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("Error listening to live status: \(error)")
                    return
                }
                
                if let document = documentSnapshot, document.exists {
                    do {
                        let decodedLive = try document.data(as: GrowattLiveStatus.self)
                        DispatchQueue.main.async {
                            self.live.liveStatus = decodedLive
                            if let disCmd = decodedLive.data?.disChargePowerCommand, let cmdVal = Double(disCmd) {
                                self.live.dischargePowerKw = String(format: "%.1fkW", (cmdVal / 100.0) * 5.0)
                            }
                            if let chgCmd = decodedLive.data?.chargePowerCommand, let cmdVal = Double(chgCmd) {
                                self.live.chargePowerKw = String(format: "%.1fkW", (cmdVal / 100.0) * 5.0)
                            }
                        }
                    } catch {
                        print("Error decoding live status: \(error)")
                    }
                }
            }

        // 3b. Listen to status/tesla_live
        teslaLiveListener = db.collection("status").document("tesla_live")
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("Error listening to tesla live status: \(error)")
                    return
                }
                if let document = documentSnapshot, document.exists {
                    do {
                        let decodedTesla = try document.data(as: TeslaStatus.self)
                        DispatchQueue.main.async {
                            self.live.teslaStatus = decodedTesla
                        }
                    } catch {
                        print("Error decoding tesla status: \(error)")
                    }
                }
            }
            
        // 4. Listen to logs collection (latest 10 logs)
        logsListener = db.collection("sync_logs")
            .order(by: "timestamp", descending: true)
            .limit(to: 10)
            .addSnapshotListener { [weak self] querySnapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("Error listening to logs: \(error)")
                    return
                }
                
                guard let documents = querySnapshot?.documents else { return }
                
                let fetchedLogs = documents.compactMap { doc -> SyncLog? in
                    do {
                        var log = try doc.data(as: SyncLog.self)
                        log.id = doc.documentID
                        return log
                    } catch {
                        print("Error decoding log entry: \(error)")
                        return nil
                    }
                }
                
                DispatchQueue.main.async {
                    self.live.logs = fetchedLogs
                }
            }
            
        // 5. Listen to telemetry history (latest 100 logs, sorted by timestamp ascending for charts)
        telemetryListener = db.collection("telemetry_history")
            .order(by: "timestamp", descending: true)
            .limit(to: 300)
            .addSnapshotListener { [weak self] querySnapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("Error listening to telemetry history: \(error)")
                    return
                }
                
                guard let documents = querySnapshot?.documents else { return }
                
                let fetchedTelemetry = documents.compactMap { doc -> TelemetryEntry? in
                    do {
                        var entry = try doc.data(as: TelemetryEntry.self)
                        entry.id = doc.documentID
                        return entry
                    } catch {
                        print("Error decoding telemetry: \(error)")
                        return nil
                    }
                }
                
                // Sort ascending (past -> present) for charts
                let sortedTelemetry = fetchedTelemetry.reversed()
                
                DispatchQueue.main.async {
                    let entries = Array(sortedTelemetry)
                    self.live.telemetryHistory = entries
                    self.saveTelemetryCache(entries)
                }
            }

        // 6. Listen to the inverter settings mirror — charge stop SoC / discharge floor
        // for the dashboard's management-state readout. Parsed as a raw dictionary with
        // tolerant key lookup (payload shape differs between legacy and token modes).
        inverterSettingsListener = db.collection("status").document("growatt_inverter_settings")
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let self = self, let data = documentSnapshot?.data() else { return }
                let settings = data["settings"] as? [String: Any] ?? [:]
                let obj = (settings["obj"] as? [String: Any]) ?? settings

                func intString(_ keys: [String]) -> String? {
                    for key in keys {
                        if let v = obj[key] {
                            if let i = v as? Int { return String(i) }
                            if let d = v as? Double { return String(Int(d)) }
                            if let s = v as? String, !s.isEmpty { return s }
                        }
                    }
                    return nil
                }

                // loadFirstStopSocSet is the ACTUAL load-first discharge floor (verified: 10).
                // wchargeSOCLowLimit2 tracks the DEVICE's effective charge target (limit1 is
                // a server-side command cache — proven stale while the device held 90).
                let chg = intString(["wchargeSOCLowLimit2", "wchargeSOCLowLimit1"])
                let dis = intString(["loadFirstStopSocSet"])

                // Power limits: command % of pmax (e.g. 100% x 5000 W = 5.0 kW)
                func powerKw(_ commandKeys: [String]) -> String? {
                    guard let cmdStr = intString(commandKeys), let cmd = Double(cmdStr) else { return nil }
                    let pmax = Double(intString(["pmax"]) ?? "5000") ?? 5000.0
                    guard pmax > 0 else { return nil }
                    return String(format: "%.1fkW", cmd / 100.0 * pmax / 1000.0)
                }
                let chgKw = powerKw(["chargePowerCommand"])
                let disKw = powerKw(["disChargePowerCommand", "dischargePowerCommand"])

                DispatchQueue.main.async {
                    self.live.chargeStopSoc = chg
                    self.live.dischargeStopSoc = dis
                    self.live.chargePowerKw = chgKw
                    self.live.dischargePowerKw = disKw
                }
            }

        // 7. Listen to the latest weather forecast snapshot (for the 24h forecast card)
        forecastListener = db.collection("weather_forecast")
            .order(by: "issued_at", descending: true)
            .limit(to: 1)
            .addSnapshotListener { [weak self] querySnapshot, error in
                guard let self = self, let doc = querySnapshot?.documents.first else { return }
                let data = doc.data()
                let issuedAt = (data["issued_at"] as? Timestamp)?.dateValue()
                let tzName = (data["timezone"] as? String) ?? self.settings.timezone

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
                formatter.timeZone = TimeZone(identifier: tzName) ?? .current

                func dbl(_ dict: [String: Any], _ key: String) -> Double? {
                    if let d = dict[key] as? Double { return d }
                    if let i = dict[key] as? Int { return Double(i) }
                    return nil
                }

                var hours: [ForecastHour] = []
                for entry in (data["hours"] as? [[String: Any]]) ?? [] {
                    guard let ts = entry["time"] as? String, let time = formatter.date(from: ts) else { continue }
                    hours.append(ForecastHour(
                        time: time,
                        gti: dbl(entry, "global_tilted_irradiance_wm2") ?? dbl(entry, "shortwave_radiation_wm2"),
                        tempC: dbl(entry, "temperature_c"),
                        precipMm: dbl(entry, "precipitation_mm"),
                        cloudPct: dbl(entry, "cloud_cover_pct"),
                        weatherCode: (entry["weather_code"] as? Int) ?? Int(dbl(entry, "weather_code") ?? -1),
                        isDay: (entry["is_day"] as? Bool) ?? false
                    ))
                }
                DispatchQueue.main.async {
                    self.forecastHours = hours
                    self.forecastIssuedAt = issuedAt
                }
            }

        // 8. Listen to the nightly advisory charging plan
        print("ChargingPlan: registering listener on status/charging_plan")
        chargingPlanListener = db.collection("status").document("charging_plan")
            .addSnapshotListener { [weak self] documentSnapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("ChargingPlan: listener error: \(error)")
                    return
                }
                guard let document = documentSnapshot else {
                    print("ChargingPlan: nil snapshot")
                    return
                }
                guard document.exists else {
                    print("ChargingPlan: document does not exist")
                    return
                }
                do {
                    let plan = try document.data(as: ChargingPlan.self)
                    print("ChargingPlan: decoded OK — for_date=\(plan.for_date), target=\(plan.target_soc)%, tasks=\(plan.suggested_tasks.count)")
                    DispatchQueue.main.async {
                        self.chargingPlan = plan
                    }
                } catch {
                    print("ChargingPlan: DECODE FAILED: \(error)")
                }
            }

        // 9. Listen to historical charging plans (charging_plan_history)
        chargingPlanHistoryListener = db.collection("charging_plan_history")
            .order(by: "for_date", descending: true)
            .limit(to: 30)
            .addSnapshotListener { [weak self] querySnapshot, error in
                guard let self = self, let docs = querySnapshot?.documents else { return }
                let plans = docs.compactMap { doc -> ChargingPlan? in
                    try? doc.data(as: ChargingPlan.self)
                }
                DispatchQueue.main.async {
                    self.chargingPlanHistory = plans
                }
            }

        // 10. Automatically listen to the past 30 days of daily bills so historical data is always preloaded
        let cal = Calendar.current
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        listenToBillsRange(start: thirtyDaysAgo, end: Date())
    }

    /// Applies the advisory plan as a ONE-SHOT override for exactly plan.for_date.
    /// Manual weekly tasks are never touched: the cloud resolver gives AI tasks priority
    /// on the applied date and ignores them on every other date, so the weekly schedule
    /// resumes by itself the day after. Re-applying replaces previous AI tasks.
    func applyChargingPlan() {
        guard let plan = chargingPlan, !plan.suggested_tasks.isEmpty else { return }
        var tasks = settings.tasks.filter { !$0.name.hasPrefix("AI Plan:") }

        for st in plan.suggested_tasks {
            var t = GrowattTask()
            t.name = "AI Plan: " + st.name
            t.days = st.days
            t.start_time = st.start_time
            t.end_time = st.end_time
            t.power = st.power
            t.soc = st.soc
            t.enabled = true
            tasks.append(t)
        }
        settings.tasks = tasks
        settings.ai_plan_applied_for = plan.for_date
        saveSettings(settings)

        // Mark the archived plan as applied, snapshotting the numbers AS APPLIED — the
        // history doc itself holds the latest *generated* plan, which may be regenerated
        // later without being re-applied; evaluation must compare actuals against what
        // actually ran, not the newest generation.
        if settings.username != "demo@xgrowatt.com" {
            db.collection("charging_plan_history").document(plan.for_date).setData([
                "applied": true,
                "applied_at": Date(),
                "applied_target_soc": plan.target_soc,
                "applied_charge_kwh": plan.charge_kwh,
                "applied_est_day_cost": plan.est_day_cost ?? plan.est_cost,
                "applied_windows": plan.suggested_tasks.map { "\($0.start_time)-\($0.end_time)→\($0.soc)%" },
            ], merge: true)
        }
    }

    func updateTeslaContinueCharge(_ enabled: Bool) {
        db.collection("status").document("charging_plan").updateData(["tesla_continue_charge": enabled])
        db.collection("settings").document("tesla").setData(["sponge_continue_charge": enabled], merge: true)
        self.chargingPlan?.tesla_continue_charge = enabled
    }

    /// One-tap cancel of the one-shot override: removes AI Plan tasks and clears the
    /// override date. Manual weekly tasks were never modified, so nothing to restore.
    func revertChargingPlan() {
        settings.tasks = settings.tasks.filter { !$0.name.hasPrefix("AI Plan:") }
        settings.ai_plan_applied_for = ""
        saveSettings(settings)

        if settings.username != "demo@xgrowatt.com", let plan = chargingPlan {
            db.collection("charging_plan_history").document(plan.for_date)
                .setData(["applied": false], merge: true)
        }
    }

    /// Whether any applied AI Plan tasks currently exist in the schedule.
    var hasAppliedAiPlan: Bool {
        settings.tasks.contains { $0.name.hasPrefix("AI Plan:") }
    }

    func saveSettings(_ newSettings: GrowattSettings) {
        if newSettings.username == "demo@xgrowatt.com" {
            self.settings = newSettings
            UserDefaults.standard.set(true, forKey: "useDemoMode")
            
            // Clear real listeners
            settingsListener?.remove()
            statusListener?.remove()
            liveStatusListener?.remove()
            logsListener?.remove()
            telemetryListener?.remove()
            billsListener?.remove()
            
            self.isAuthenticated = true
            loadMockData()
            return
        }
        
        UserDefaults.standard.set(false, forKey: "useDemoMode")
        do {
            try db.collection("settings").document("growatt").setData(from: newSettings)
            print("Settings saved successfully to Firestore.")
            
            // Re-listen if switching back from demo mode
            if !self.isAuthenticated {
                authenticateAndListen()
            }
        } catch {
            print("Error saving settings: \(error)")
            self.errorMessage = "Failed to save settings: \(error.localizedDescription)"
        }
    }
    
    /// Manually re-runs the charging-plan generator (e.g. after the 05:00 forecast update).
    /// The result lands in status/charging_plan, which the snapshot listener picks up —
    /// no need to parse the callable response.
    func regenerateChargingPlan() {
        if settings.username == "demo@xgrowatt.com" {
            DispatchQueue.main.async { self.isRegeneratingPlan = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.isRegeneratingPlan = false }
            return
        }
        guard isAuthenticated else { return }

        DispatchQueue.main.async { self.isRegeneratingPlan = true }

        Auth.auth().currentUser?.getIDToken { [weak self] token, error in
            guard let self = self else { return }
            guard let token = token, error == nil else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to fetch ID token: \(error?.localizedDescription ?? "nil token")"
                    self.isRegeneratingPlan = false
                }
                return
            }

            let urlString = "https://australia-southeast1-demo-solar-microgrid.cloudfunctions.net/trigger_generate_charging_plan"
            guard let url = URL(string: urlString) else {
                DispatchQueue.main.async { self.isRegeneratingPlan = false }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["data": [:]])

            URLSession.shared.dataTask(with: request) { _, _, error in
                DispatchQueue.main.async {
                    self.isRegeneratingPlan = false
                    if let error = error {
                        self.errorMessage = "Plan regeneration failed: \(error.localizedDescription)"
                    }
                }
            }.resume()
        }
    }

    func triggerManualSync(mode: String = "sync") {
        if settings.username == "demo@xgrowatt.com" {
            DispatchQueue.main.async {
                self.live.isSyncing = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.loadMockData()
                self.live.isSyncing = false
            }
            return
        }
        
        guard isAuthenticated else { return }

        DispatchQueue.main.async {
            self.live.isSyncing = true
        }
        
        Auth.auth().currentUser?.getIDToken { [weak self] token, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to fetch ID token: \(error.localizedDescription)"
                    self.live.isSyncing = false
                }
                return
            }
            
            guard let token = token else {
                DispatchQueue.main.async {
                    self.errorMessage = "Token is nil"
                    self.live.isSyncing = false
                }
                return
            }
            
            let urlString = "https://australia-southeast1-demo-solar-microgrid.cloudfunctions.net/trigger_growatt_sync_now"
            guard let url = URL(string: urlString) else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            // Firebase HTTPS callable expects parameter wrapped in data
            let requestBody: [String: Any] = ["data": ["mode": mode]]
            request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    self.live.isSyncing = false
                }
                
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = "Sync Request Failed: \(error.localizedDescription)"
                    }
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        print("Manual sync triggered successfully with mode: \(mode)")
                    } else {
                        print("Manual sync returned code: \(httpResponse.statusCode)")
                        DispatchQueue.main.async {
                            self.errorMessage = "Sync Error: Server returned status \(httpResponse.statusCode)"
                        }
                    }
                }
            }.resume()
        }
    }

    func refreshTeslaStatus() {
        guard isAuthenticated else { return }
        DispatchQueue.main.async { self.isRefreshingTesla = true }

        Auth.auth().currentUser?.getIDToken { [weak self] token, error in
            guard let self = self else { return }
            guard let token = token, error == nil else {
                DispatchQueue.main.async { self.isRefreshingTesla = false }
                return
            }

            let urlString = "https://australia-southeast1-demo-solar-microgrid.cloudfunctions.net/poll_tesla_status"
            guard let url = URL(string: urlString) else {
                DispatchQueue.main.async { self.isRefreshingTesla = false }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 30

            URLSession.shared.dataTask(with: request) { _, response, error in
                DispatchQueue.main.async {
                    self.isRefreshingTesla = false
                    if let error = error {
                        self.errorMessage = "Tesla refresh failed: \(error.localizedDescription)"
                    }
                    // Firestore listener auto-updates tesla_live when Cloud Function writes fresh data
                }
            }.resume()
        }
    }

    // MARK: - Demo Mode Mock Data Generator
    func loadMockData() {
        // 1. Create mock status
        self.live.status = GrowattStatus(
            last_run: Date(),
            status: "success",
            message: "Schedules successfully synchronized (Demo Mode)",
            applied_schedule: "[00:00-06:00 (100% SoC, 100% Power)]",
            params: [],
            trigger: "manual"
        )

        // 2. Create mock logs list
        self.live.logs = [
            SyncLog(id: "mock_log_1", timestamp: Date().addingTimeInterval(-3600 * 2), status: "success", message: "Automated schedule sync successful.", applied_schedule: "[00:00-06:00 (100% SoC)]", trigger: "cron"),
            SyncLog(id: "mock_log_2", timestamp: Date().addingTimeInterval(-3600 * 6), status: "success", message: "Inverter parameters fetched: Battery SoC: 45%.", applied_schedule: nil, trigger: "read"),
            SyncLog(id: "mock_log_3", timestamp: Date().addingTimeInterval(-3600 * 12), status: "success", message: "Battery low-SoC safety check completed.", applied_schedule: nil, trigger: "cron")
        ]
        
        // 2b. Create mock charging plan (so the Smart Charging Plan card shows in demo mode)
        var mockPlanTask = ChargingPlanTask()
        mockPlanTask.name = "Off-peak charge (Demo)"
        mockPlanTask.days = [DateFormatter.eee.string(from: Date().addingTimeInterval(86400))]
        mockPlanTask.start_time = "00:00"
        mockPlanTask.end_time = "06:00"
        mockPlanTask.power = "100"
        mockPlanTask.soc = "61"
        var mockPlan = ChargingPlan()
        mockPlan.generated_at = Date()
        mockPlan.for_date = DateFormatter.yyyyMMdd.string(from: Date().addingTimeInterval(86400))
        mockPlan.soc_now = 81
        mockPlan.battery_rated_kwh = 30
        mockPlan.target_soc = 61
        mockPlan.charge_kwh = 3.66
        mockPlan.est_cost = 0.42
        mockPlan.offpeak_rate = 0.11
        mockPlan.pv_forecast_kwh = 12.0
        mockPlan.load_forecast_kwh = 24.2
        mockPlan.model_used = "empirical_formula"
        mockPlan.suggested_tasks = [mockPlanTask]
        mockPlan.reasoning = [
            "Horizon: 06:00 -> Sat 00:00 (next cheap/free import window).",
            "Predicted over horizon: PV 12.0 kWh vs load 24.2 kWh (worst cumulative deficit 12.2 kWh).",
            "Need 15.2 kWh at 06:00 (incl. 10% reserve) + 10% margin -> target SoC 61%.",
            "Battery expected at midnight: 14.6 kWh (49%) -> grid charge 3.7 kWh ≈ $0.42 at 0.11/kWh.",
        ]
        mockPlan.mode = "advisory"
        self.chargingPlan = mockPlan

        // 3. Create mock telemetry history
        var mockEntries: [TelemetryEntry] = []
        let calendar = Calendar.current
        let today = Date()
        
        // Start 24 hours ago, step 5 minutes
        let stepSeconds: TimeInterval = 5 * 60
        let totalSteps = Int((24 * 3600) / stepSeconds) // 288 steps
        
        var currentSoc = 45.0
        
        for step in 0..<totalSteps {
            let offset = TimeInterval(step - totalSteps) * stepSeconds
            let date = today.addingTimeInterval(offset)
            
            // Get hour representation
            let hour = Double(calendar.component(.hour, from: date)) + Double(calendar.component(.minute, from: date)) / 60.0
            
            // Solar Generation (follows sine curve from 6 AM to 6 PM)
            var solar = 0.0
            if hour >= 6.0 && hour <= 18.0 {
                let radians = (hour - 6.0) / 12.0 * Double.pi
                solar = sin(radians) * 2.2 * Double.random(in: 0.85...1.15)
            }
            
            // Home Consumption / Load (peaks at 8 AM, 1 PM, 7 PM)
            var load = 0.35
            if hour >= 7.0 && hour <= 9.0 {
                load += 1.8 * sin((hour - 7.0) / 2.0 * Double.pi)
            } else if hour >= 12.0 && hour <= 14.0 {
                load += 1.2 * sin((hour - 12.0) / 2.0 * Double.pi)
            } else if hour >= 17.5 && hour <= 21.0 {
                load += 2.8 * sin((hour - 17.5) / 3.5 * Double.pi)
            }
            load *= Double.random(in: 0.9...1.1)
            
            // Charge / Discharge
            var charge = 0.0
            var discharge = 0.0
            var gridImport = 0.0
            var gridExport = 0.0
            
            let netSolar = solar - load
            if netSolar > 0 {
                if currentSoc < 100.0 {
                    let possibleCharge = min(netSolar, 3.0)
                    charge = possibleCharge
                    currentSoc += (charge * (5.0 / 60.0) / 19.5) * 100.0
                    gridExport = netSolar - possibleCharge
                } else {
                    gridExport = netSolar
                }
            } else {
                let deficit = abs(netSolar)
                if currentSoc > 10.0 {
                    let possibleDischarge = min(deficit, 4.0)
                    discharge = possibleDischarge
                    currentSoc -= (discharge * (5.0 / 60.0) / 19.5) * 100.0
                    gridImport = deficit - possibleDischarge
                } else {
                    gridImport = deficit
                }
            }
            
            currentSoc = max(10.0, min(100.0, currentSoc))
            
            let entry = TelemetryEntry(
                id: "mock_\(step)",
                timestamp: date,
                soc: Int(currentSoc),
                battery_energy_kwh: (currentSoc / 100.0) * 19.5,
                battery_voltage: 51.2 + (currentSoc / 100.0) * 4.2,
                solar_generation_kw: solar,
                charge_power_kw: charge,
                discharge_power_kw: discharge,
                local_load_kw: load,
                grid_export_kw: gridExport,
                grid_import_kw: gridImport
            )
            mockEntries.append(entry)
        }
        
        self.live.telemetryHistory = mockEntries

        // Update liveStatus with the last entry's values
        if let last = mockEntries.last {
            self.live.liveStatus = GrowattLiveStatus(
                last_updated: Date(),
                device_sn: "DEMO_SPH_INVERTER_SN (Demo)",
                plant_id: "DEMO_PLANT_1",
                data: GrowattLiveStatus.LiveDataFields(
                    SOC: String(last.soc),
                    ppv: String(format: "%.2f", last.solar_generation_kw),
                    chargePower: String(format: "%.2f", last.charge_power_kw),
                    dischargePower: String(format: "%.2f", last.discharge_power_kw),
                    localLoad: String(format: "%.2f", last.local_load_kw),
                    gridExport: String(format: "%.2f", last.grid_export_kw),
                    gridImport: String(format: "%.2f", last.grid_import_kw)
                )
            )
        }
    }
    
    func listenToBillsRange(start: Date, end: Date) {
        billsListener?.remove()
        
        if settings.username == "demo@xgrowatt.com" {
            generateMockBills(start: start, end: end)
            return
        }
        
        let startStr = DateFormatter.yyyyMMdd.string(from: start)
        let endStr = DateFormatter.yyyyMMdd.string(from: end)
        
        billsListener = db.collection("daily_bills")
            .whereField("date", isGreaterThanOrEqualTo: startStr)
            .whereField("date", isLessThanOrEqualTo: endStr)
            .addSnapshotListener { [weak self] querySnapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("Error listening to bills range: \(error)")
                    return
                }
                
                guard let documents = querySnapshot?.documents else { return }
                
                let fetchedBills = documents.compactMap { doc -> DailyBill? in
                    try? doc.data(as: DailyBill.self)
                }
                
                let sortedBills = fetchedBills.sorted(by: { $0.date < $1.date })
                
                DispatchQueue.main.async {
                    var billMap = Dictionary(uniqueKeysWithValues: self.historicalBills.map { ($0.date, $0) })
                    for bill in sortedBills {
                        billMap[bill.date] = bill
                    }
                    let merged = billMap.values.sorted(by: { $0.date < $1.date })
                    self.historicalBills = merged
                    self.saveBillsCache(merged)
                }
            }
    }
    func triggerBackfillBills(startDate: String, endDate: String, onComplete: @escaping (Bool, String) -> Void = { _, _ in }) {
        Auth.auth().currentUser?.getIDToken { token, error in
            guard let token = token, error == nil else {
                DispatchQueue.main.async {
                    onComplete(false, error?.localizedDescription ?? "Authentication error")
                }
                return
            }
            guard let url = URL(string: "https://australia-southeast1-demo-solar-microgrid.cloudfunctions.net/trigger_backfill_bills") else {
                DispatchQueue.main.async {
                    onComplete(false, "Invalid URL")
                }
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["data": ["start_date": startDate, "end_date": endDate]])

            URLSession.shared.dataTask(with: request) { _, _, err in
                DispatchQueue.main.async {
                    if let err = err {
                        onComplete(false, err.localizedDescription)
                    } else {
                        onComplete(true, "Backfill completed.")
                    }
                }
            }.resume()
        }
    }
    
    private func generateMockBills(start: Date, end: Date) {
        var mockList: [DailyBill] = []
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        var current = calendar.startOfDay(for: start)
        let finalEnd = calendar.startOfDay(for: end)
        
        while current <= finalEnd {
            let dateStr = formatter.string(from: current)
            
            let solar = Double.random(in: 12.0...25.0)
            let load = Double.random(in: 10.0...18.0)
            let charge = Double.random(in: 4.0...7.0)
            let discharge = Double.random(in: 3.5...6.5)
            
            let gridImport = max(0.0, load - solar * 0.4 - discharge)
            let gridExport = max(0.0, solar - charge - load * 0.4)
            
            let supply = 0.95
            let impRate = 0.32
            let expRate = 0.08
            
            let impCost = gridImport * impRate
            let expCredit = gridExport * expRate
            let netCost = impCost - expCredit + supply
            let savings = max(0.0, (load - gridImport) * impRate)
            let arbitrage = discharge * 0.14
            
            mockList.append(DailyBill(
                date: dateStr,
                timestamp: current,
                solar_kwh: round(solar * 100) / 100,
                load_kwh: round(load * 100) / 100,
                import_kwh: round(gridImport * 100) / 100,
                export_kwh: round(gridExport * 100) / 100,
                charge_kwh: round(charge * 100) / 100,
                discharge_kwh: round(discharge * 100) / 100,
                net_cost: round(netCost * 100) / 100,
                savings: round(savings * 100) / 100,
                arbitrage: round(arbitrage * 100) / 100,
                daily_supply_charge: supply,
                import_cost: round(impCost * 100) / 100,
                export_credit: round(expCredit * 100) / 100
            ))
            
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = nextDay
        }
        
        DispatchQueue.main.async {
            self.historicalBills = mockList
        }
    }
}
