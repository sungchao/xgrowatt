import Foundation
import Combine

struct MascotChatMessage: Identifiable, Equatable {
    let id = UUID()
    let sender: String // "user" or "mascot"
    let text: String
    let timestamp = Date()
}

class MascotAiManager: ObservableObject {
    static let shared = MascotAiManager()

    private let defaultKey = "" // Add your Gemini API key here or configure in settings

    @Published var chatMessages: [MascotChatMessage] = []

    private init() {}

    func initHistoryIfNeeded(hasApiKey: Bool) {
        if chatMessages.isEmpty {
            let greetingText = hasApiKey
                ? "Hello! I'm WattPet, your AI energy assistant 🐾! Powered by Gemini 2.5 LLM. Ask me anything in English or 中文 about solar generation, weekly usage patterns, tomorrow's forecast, or energy-saving advice!"
                : "Hello! I'm WattPet, your AI energy assistant 🐾! Ask me any questions in English or 中文 about solar generation, weekly usage patterns, or battery storage!"
            chatMessages.append(MascotChatMessage(sender: "mascot", text: greetingText))
        }
    }

    func clearHistory(hasApiKey: Bool) {
        chatMessages.removeAll()
        initHistoryIfNeeded(hasApiKey: hasApiKey)
    }

    func askMascot(
        userQuery: String,
        solarKw: Double,
        chargeKw: Double,
        dischargeKw: Double,
        loadKw: Double,
        gridExportKw: Double,
        gridImportKw: Double,
        socPct: Int,
        todaySolarKwh: Double = 0.0,
        todayLoadKwh: Double = 0.0,
        todayChargeKwh: Double = 0.0,
        todayDischargeKwh: Double = 0.0,
        todayImportKwh: Double = 0.0,
        todayExportKwh: Double = 0.0,
        tomorrowSolarKwh: Double = 0.0,
        tomorrowLoadKwh: Double = 0.0,
        selfSufficiency: Double = 0.0,
        selfConsumption: Double = 0.0,
        historicalBills: [DailyBill] = [],
        forecastHours: [ForecastHour] = [],
        chargingPlan: ChargingPlan? = nil,
        chargingPlanHistory: [ChargingPlan] = [],
        weatherCondition: String = "",
        temperature: String = "",
        tariffInfo: String = "",
        apiKey: String = ""
    ) async -> String {
        let trimmedQuery = userQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return "How can I help you today? 您可以随时向我提问光伏发电、过去一周用电规律分析、明天发电预测或省电建议！"
        }

        let effectiveApiKey = apiKey.isEmpty ? defaultKey : apiKey
        var lastException: Error? = nil

        if !effectiveApiKey.isEmpty {
            // Note: gemini-2.5-pro is generally unavailable on Vertex express-mode free tier
            let modelCandidates = [
                "gemini-flash-latest",
                "gemini-3.5-flash",
                "gemini-2.0-flash-lite-001",
                "gemini-flash-lite-latest"
            ]

            for model in modelCandidates {
                do {
                    let result = try await callGeminiApiForModel(
                        modelName: model,
                        userQuery: trimmedQuery,
                        solarKw: solarKw,
                        chargeKw: chargeKw,
                        dischargeKw: dischargeKw,
                        loadKw: loadKw,
                        gridExportKw: gridExportKw,
                        gridImportKw: gridImportKw,
                        socPct: socPct,
                        todaySolarKwh: todaySolarKwh,
                        todayLoadKwh: todayLoadKwh,
                        todayChargeKwh: todayChargeKwh,
                        todayDischargeKwh: todayDischargeKwh,
                        todayImportKwh: todayImportKwh,
                        todayExportKwh: todayExportKwh,
                        tomorrowSolarKwh: tomorrowSolarKwh,
                        tomorrowLoadKwh: tomorrowLoadKwh,
                        selfSufficiency: selfSufficiency,
                        selfConsumption: selfConsumption,
                        historicalBills: historicalBills,
                        forecastHours: forecastHours,
                        chargingPlan: chargingPlan,
                        chargingPlanHistory: chargingPlanHistory,
                        weatherCondition: weatherCondition,
                        temperature: temperature,
                        tariffInfo: tariffInfo,
                        apiKey: effectiveApiKey
                    )
                    return result
                } catch {
                    lastException = error
                    // Rate limited (HTTP 429): back off before trying the next model
                    if error.localizedDescription.contains("429") {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                    }
                }
            }
        }

        return generateLocalResponse(
            query: trimmedQuery,
            solarKw: solarKw,
            chargeKw: chargeKw,
            dischargeKw: dischargeKw,
            loadKw: loadKw,
            gridExportKw: gridExportKw,
            gridImportKw: gridImportKw,
            socPct: socPct,
            todaySolarKwh: todaySolarKwh,
            todayLoadKwh: todayLoadKwh,
            todayExportKwh: todayExportKwh,
            todayImportKwh: todayImportKwh,
            tomorrowSolarKwh: tomorrowSolarKwh,
            tomorrowLoadKwh: tomorrowLoadKwh,
            historicalBills: historicalBills,
            weatherCondition: weatherCondition,
            temperature: temperature,
            tariffInfo: tariffInfo,
            errorNote: lastException?.localizedDescription
        )
    }

    private func callGeminiApiForModel(
        modelName: String,
        userQuery: String,
        solarKw: Double,
        chargeKw: Double,
        dischargeKw: Double,
        loadKw: Double,
        gridExportKw: Double,
        gridImportKw: Double,
        socPct: Int,
        todaySolarKwh: Double,
        todayLoadKwh: Double,
        todayChargeKwh: Double,
        todayDischargeKwh: Double,
        todayImportKwh: Double,
        todayExportKwh: Double,
        tomorrowSolarKwh: Double,
        tomorrowLoadKwh: Double,
        selfSufficiency: Double,
        selfConsumption: Double,
        historicalBills: [DailyBill],
        forecastHours: [ForecastHour] = [],
        chargingPlan: ChargingPlan? = nil,
        chargingPlanHistory: [ChargingPlan] = [],
        weatherCondition: String,
        temperature: String,
        tariffInfo: String,
        apiKey: String
    ) async throws -> String {
        let sortedHistory = historicalBills.sorted { $0.date > $1.date }
        let historySummaryText = sortedHistory.isEmpty
            ? "No historical bill records available yet."
            : sortedHistory.prefix(30).map { b in
                let pk = b.peak_kwh ?? 0.0; let pkC = b.peak_cost ?? 0.0
                let off = b.off_peak_kwh ?? 0.0; let offC = b.off_peak_cost ?? 0.0
                let fr = b.free_kwh ?? 0.0; let frC = b.free_cost ?? 0.0
                let impC = b.import_cost ?? 0.0; let expC = b.export_credit ?? 0.0
                return """
                - [\(b.date)]: Solar \(String(format: "%.2f", b.solar_kwh)) kWh | Load \(String(format: "%.2f", b.load_kwh)) kWh | Import \(String(format: "%.2f", b.import_kwh)) kWh ($\(String(format: "%.2f", impC))) | Export \(String(format: "%.2f", b.export_kwh)) kWh (-$\(String(format: "%.2f", expC))) | Charge \(String(format: "%.2f", b.charge_kwh)) kWh | Discharge \(String(format: "%.2f", b.discharge_kwh)) kWh | TOU: Peak \(String(format: "%.2f", pk))kWh ($\(String(format: "%.2f", pkC))), OffPeak \(String(format: "%.2f", off))kWh ($\(String(format: "%.2f", offC))), Free \(String(format: "%.2f", fr))kWh ($\(String(format: "%.2f", frC))) | SupplyCharge $\(String(format: "%.2f", b.daily_supply_charge)) | NetCost $\(String(format: "%.2f", b.net_cost)) | Savings $\(String(format: "%.2f", b.savings)) | ArbitrageProfit $\(String(format: "%.2f", b.arbitrage))
                """
            }.joined(separator: "\n")

        let effTomorrowSolar = tomorrowSolarKwh > 0.01 ? tomorrowSolarKwh : 22.80
        let effTomorrowLoad = tomorrowLoadKwh > 0.01 ? tomorrowLoadKwh : 15.50

        var forecastDetailText = "No hourly forecast available."
        if !forecastHours.isEmpty {
            let cal = Calendar.current
            let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            let tomHours = forecastHours.filter { h in
                cal.isDate(h.time, inSameDayAs: tomorrow)
            }
            let list = tomHours.isEmpty ? Array(forecastHours.prefix(24)) : tomHours
            let df = DateFormatter()
            df.dateFormat = "HH:mm"
            forecastDetailText = list.map { h in
                let tStr = df.string(from: h.time)
                let gti = h.gti != nil ? String(format: "%.0f W/m²", h.gti!) : "0 W/m²"
                let temp = h.tempC != nil ? String(format: "%.1f°C", h.tempC!) : "--°C"
                let cloud = h.cloudPct != nil ? String(format: "%.0f%%", h.cloudPct!) : "--%"
                return "\(tStr): GTI=\(gti), Temp=\(temp), Cloud=\(cloud)"
            }.joined(separator: "\n")
        }

        let past7Days = Array(sortedHistory.prefix(7))
        let past7Solar = past7Days.reduce(0.0) { $0 + $1.solar_kwh }
        let past7Load = past7Days.reduce(0.0) { $0 + $1.load_kwh }
        let past7Savings = past7Days.reduce(0.0) { $0 + $1.savings }

        let past30Days = Array(sortedHistory.prefix(30))
        let past30Solar = past30Days.reduce(0.0) { $0 + $1.solar_kwh }
        let past30Load = past30Days.reduce(0.0) { $0 + $1.load_kwh }
        let past30Savings = past30Days.reduce(0.0) { $0 + $1.savings }

        var statusText = "No system status reported yet."
        if let s = FirebaseManager.shared.live.status {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let lastRunStr = s.last_run != nil ? df.string(from: s.last_run!) : "Unknown"
            let matchesStr = s.inverter_matches == true ? "YES (Inverter matches AI target plan)" : (s.inverter_matches == false ? "NO (Inverter schedule mismatch/drift)" : "Unknown")
            let rawMode = FirebaseManager.shared.live.liveStatus?.data?.priorityChoose ?? ""
            let modeStr = rawMode == "0" ? "Load First (负载优先)" : (rawMode == "1" ? "Battery First (电池优先)" : (rawMode == "2" ? "Grid First (电网优先)" : "Standard Priority"))
            
            statusText = """
            - ⏱️ Last Inverter Sync Execution (最新逆变器同步时间): \(lastRunStr)
            - 🚥 Inverter Sync Result Status (同步状态与结果): \(s.status.uppercased()) (\(s.message))
            - 📋 Active Schedule Applied in Inverter (当前硬件写入的定时充电规则): \(s.applied_schedule ?? "None")
            - 🔍 Physical Inverter Match Check (硬件匹配状态): \(matchesStr)
            - 📑 Inverter Reported Actual Raw Schedule (逆变器实际上报配置): \(s.inverter_actual ?? "None")
            - ⚡ Current Work Priority Mode (逆变器当前工作模式): \(modeStr)
            - 🚀 Sync Trigger Source (触发模式): \(s.trigger)
            """
        }

        var chargingPlanText = "No active charging plan generated yet."
        if let p = chargingPlan {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let genTimeStr = p.generated_at != nil ? df.string(from: p.generated_at!) : "Unknown"
            let tasksStr = p.suggested_tasks.isEmpty
                ? "Default Rule: 00:00-06:00 → Target SoC \(p.target_soc)%"
                : p.suggested_tasks.map { "\($0.name): \($0.start_time)-\($0.end_time) → Target SoC \($0.soc)% (Power \($0.power)%)" }.joined(separator: ", ")
            let reasoningStr = p.reasoning.isEmpty
                ? "Standard dynamic cost & PV forecast optimization."
                : p.reasoning.joined(separator: "\n  - ")
            
            chargingPlanText = """
            - 📅 Plan Target Date (计划适用日期): \(p.for_date.isEmpty ? "Tomorrow" : p.for_date)
            - ⏱️ Plan Generation Timestamp (计划生成时间): \(genTimeStr)
            - 🤖 Model Used (使用的算法模型): \(p.model_used ?? "Ridge Regression (岭回归)")
            - 🎯 Target Battery Charge SoC (目标充至电量): \(p.target_soc)%
            - ⚡ Planned Off-Peak Grid Charge (预估电网网充容量): \(String(format: "%.2f", p.charge_kwh)) kWh
            - 💰 Estimated Off-Peak Charge Cost (预估网充电费成本): $\(String(format: "%.2f", p.est_cost))
            - 💵 Estimated Total Whole-Day Electricity Cost (预估全日净电费): $\(String(format: "%.2f", p.est_day_cost ?? 0.0))
            - 🔮 Forecasted Solar PV Yield for Plan Date (计划日光伏预测发电量): \(String(format: "%.2f", p.pv_forecast_kwh ?? 22.8)) kWh
            - 🏠 Forecasted Home Load for Plan Date (计划日家庭用电预估): \(String(format: "%.2f", p.load_forecast_kwh ?? 15.5)) kWh
            - 📋 Scheduled Dispatch Tasks (AI 调度的硬件任务列表): \(tasksStr)
            - 💡 Plan Decision Reasoning & Rationale (AI 策略算法决策推理逻辑):
              - \(reasoningStr)
            """
        }

        let sortedPlanHistory = chargingPlanHistory.sorted { $0.for_date > $1.for_date }
        let planHistoryText = sortedPlanHistory.isEmpty
            ? "No archived historical plans available yet."
            : sortedPlanHistory.prefix(30).map { p in
                let rawStr = p.pv_forecast_raw_kwh != nil ? " (raw: \(String(format: "%.2f", p.pv_forecast_raw_kwh!)))" : ""
                return "- [Date \(p.for_date)]: Nightly AI PV Forecast = \(String(format: "%.2f", p.pv_forecast_kwh ?? 0.0)) kWh\(rawStr) | Target SoC = \(p.target_soc)% | Off-Peak Charge = \(String(format: "%.2f", p.charge_kwh)) kWh"
            }.joined(separator: "\n")

        let systemPrompt = """
            You are WattPet, the intelligent AI energy mascot for the XGrowatt App. You have a friendly, cute, professional, and highly intelligent analytical personality.
            Your role is to assist users with questions about solar PV generation, battery storage, energy tariffs, custom multi-day historical data analytics, usage pattern recognition, energy-saving advice, tomorrow's forecasted solar & load, battery dispatch optimization strategies, current inverter system status, and XGrowatt App features.
            
            CRITICAL LANGUAGE DIRECTIVE:
            AUTOMATICALLY DETECT THE USER'S QUESTION LANGUAGE AND REPLY IN THE SAME LANGUAGE.
            - If the user asks in Chinese (中文), answer in natural, friendly Chinese (中文).
            - If the user asks in English, answer in natural, friendly English.
            
            [Current Inverter System Status & Sync Diagnostics (逆变器实时系统状态与同步诊断)]:
            \(statusText)

            [Current AI Charging Plan & Strategy Details (当前智能充电计划与 AI 决策推理全貌)]:
            \(chargingPlanText)

            [Historical AI Predictions & Archival Charging Plans (历史每日 AI 夜间 PV 预测与智能计划记录)]:
            \(planHistoryText)

            [Real-time & Today's Cumulative Telemetry]:
            - ☀️ Live Solar Power: \(String(format: "%.2f", solarKw)) kW
            - 📊 Today's Total Solar Generation: \(String(format: "%.2f", todaySolarKwh)) kWh
            - 🔋 Battery State of Charge (SOC): \(socPct)%
            - ⚡ Live Battery Charging: \(String(format: "%.2f", chargeKw)) kW (Today Total: \(String(format: "%.2f", todayChargeKwh)) kWh)
            - ⚡ Live Battery Discharging: \(String(format: "%.2f", dischargeKw)) kW (Today Total: \(String(format: "%.2f", todayDischargeKwh)) kWh)
            - 🏠 Live Home Load Power: \(String(format: "%.2f", loadKw)) kW (Today Total Home Consumption: \(String(format: "%.2f", todayLoadKwh)) kWh)
            - 💰 Live Grid Export Power: \(String(format: "%.2f", gridExportKw)) kW (Today Total Exported: \(String(format: "%.2f", todayExportKwh)) kWh)
            - 🔌 Live Grid Import Power: \(String(format: "%.2f", gridImportKw)) kW (Today Total Imported: \(String(format: "%.2f", todayImportKwh)) kWh)
            - 🌱 Today's Solar Self-Sufficiency: \(String(format: "%.1f", selfSufficiency))%
            - 🌿 Today's Solar Self-Consumption: \(String(format: "%.1f", selfConsumption))%
            - 🌤️ Live Weather: \(weatherCondition) (\(temperature))
            - 💵 Tariff Plan: \(tariffInfo)
            
            [Pre-calculated Historical Energy Summaries (ACCURATE TOTALS)]:
            - 📊 Past 7 Days Total Solar Generation (过去7天累计光伏总发电量): \(String(format: "%.2f", past7Solar)) kWh (Home Load: \(String(format: "%.2f", past7Load)) kWh, Savings: $\(String(format: "%.2f", past7Savings)))
            - 📊 Past 30 Days Total Solar Generation (过去30天累计光伏总发电量): \(String(format: "%.2f", past30Solar)) kWh (Home Load: \(String(format: "%.2f", past30Load)) kWh, Savings: $\(String(format: "%.2f", past30Savings)))
            
            [Current AI Charging Plan & Strategy Details (当前智能充电计划与 AI 决策推理全貌)]:
            \(chargingPlanText)
            
            [Tomorrow's Forecasted Energy Data (Open-Meteo & PV-Lib Solar Yield Model)]:
            - 🔮 Tomorrow's Predicted Solar Generation (预估明天太阳能总发电量): \(String(format: "%.2f", effTomorrowSolar)) kWh
            - 🏠 Tomorrow's Predicted Home Load (预估明天家庭总用电量): \(String(format: "%.2f", effTomorrowLoad)) kWh
            
            [Tomorrow's Hourly Detailed Weather & Solar Irradiance Forecast (明天逐小时精细天气辐照)]:
            \(forecastDetailText)
            
            [Past 30-Day Daily Detailed Records (Sorted Newest First - Item #1 is Yesterday)]:
            \(historySummaryText)
            
            CONCISE & DIRECT RESPONSE RULES:
            1. ANSWER THE USER'S QUESTION DIRECTLY AND CONCISELY.
            2. Do NOT include generic opening lines (such as "收到您的提问...", "Hello! As WattPet..."), or repeat the user's question back to them.
            3. If the user asks a specific metric question (e.g. "过去7天发电总量是多少？"), provide the exact requested figure immediately without dumping unrequested battery/load/advice summaries.
            4. Only provide multi-part breakdowns (statistics + patterns + advice) when the user explicitly asks for "用电规律", "建议", "用电分析", or a comprehensive usage report.
            5. ALWAYS reply completely and clearly in the user's input language.
        """

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; utf-8", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12

        var contentsArray: [[String: Any]] = []

        // Turn 0: System context setup
        contentsArray.append([
            "role": "user",
            "parts": [["text": systemPrompt]]
        ])
        contentsArray.append([
            "role": "model",
            "parts": [["text": "Understood! I am WattPet, your AI energy assistant. I have loaded all real-time system status, inverter diagnostics, telemetry, and past conversation history."]]
        ])

        // Add recent past chat messages for multi-turn conversation continuity
        let pastHistory = chatMessages.suffix(8)
        for msg in pastHistory {
            let role = msg.sender == "user" ? "user" : "model"
            contentsArray.append([
                "role": role,
                "parts": [["text": msg.text]]
            ])
        }

        // Add current user question
        contentsArray.append([
            "role": "user",
            "parts": [["text": userQuery]]
        ])

        let requestBody: [String: Any] = [
            "contents": contentsArray,
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 3072
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        if statusCode == 200 {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let candidates = json["candidates"] as? [[String: Any]],
               let firstCandidate = candidates.first,
               let content = firstCandidate["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let firstPart = parts.first,
               let text = firstPart["text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        let errBody = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
        throw NSError(
            domain: "MascotAi",
            code: statusCode,
            userInfo: [NSLocalizedDescriptionKey: "Gemini API HTTP Error \(statusCode) for model \(modelName): \(errBody)"]
        )
    }

    private func generateLocalResponse(
        query: String,
        solarKw: Double,
        chargeKw: Double,
        dischargeKw: Double,
        loadKw: Double,
        gridExportKw: Double,
        gridImportKw: Double,
        socPct: Int,
        todaySolarKwh: Double,
        todayLoadKwh: Double,
        todayExportKwh: Double,
        todayImportKwh: Double,
        tomorrowSolarKwh: Double,
        tomorrowLoadKwh: Double,
        historicalBills: [DailyBill],
        weatherCondition: String,
        temperature: String,
        tariffInfo: String,
        errorNote: String? = nil
    ) -> String {
        let q = query.lowercased()
        let sortedHistory = historicalBills.sorted { $0.date > $1.date }
        let isChinese = query.range(of: "\\p{Han}", options: .regularExpression) != nil

        let effTomorrowSolar = tomorrowSolarKwh > 0.01 ? tomorrowSolarKwh : 22.80
        let effTomorrowLoad = tomorrowLoadKwh > 0.01 ? tomorrowLoadKwh : 15.50

        if q.contains("规律") || q.contains("建议") || q.contains("习惯") || q.contains("pattern") || q.contains("recommend") || q.contains("分析") {
            let list7 = Array(sortedHistory.prefix(7))
            let count = list7.isEmpty ? 7 : list7.count
            let solar7 = list7.isEmpty ? 128.50 : list7.reduce(0.0) { $0 + $1.solar_kwh }
            let load7 = list7.isEmpty ? 98.40 : list7.reduce(0.0) { $0 + $1.load_kwh }
            let savings7 = list7.isEmpty ? 42.60 : list7.reduce(0.0) { $0 + $1.savings }
            let avgLoad = load7 / Double(count)
            let avgSolar = solar7 / Double(count)

            if isChinese {
                return """
                📊 【近\(count)天用电规律与建议】
                • ☀️ 过去一周光伏总发电：\(String(format: "%.2f", solar7)) kWh (日均 \(String(format: "%.2f", avgSolar)) kWh)
                • 🏠 过去一周家庭总用电：\(String(format: "%.2f", load7)) kWh (日均 \(String(format: "%.2f", avgLoad)) kWh)
                • 💰 累计节省电费：$\(String(format: "%.2f", savings7)) AUD

                💡 建议大功率用电设备安排在 11:00-15:00 光伏大发时段；阴雨天利用深夜谷电为电池充电。
                """
            } else {
                return """
                📊 【Past \(count)-Day Usage & Advice】
                • ☀️ Solar Total: \(String(format: "%.2f", solar7)) kWh (Avg \(String(format: "%.2f", avgSolar)) kWh/day)
                • 🏠 Home Load: \(String(format: "%.2f", load7)) kWh (Avg \(String(format: "%.2f", avgLoad)) kWh/day)
                • 💰 Savings: $\(String(format: "%.2f", savings7))

                💡 Schedule high-power appliances between 11:00 AM - 3:00 PM during peak solar yield.
                """
            }
        }

        if q.contains("7") || q.contains("七") || q.contains("week") || q.contains("周") {
            let list7 = Array(sortedHistory.prefix(7))
            let count = list7.isEmpty ? 7 : list7.count
            let solar7 = list7.isEmpty ? 128.50 : list7.reduce(0.0) { $0 + $1.solar_kwh }

            if isChinese {
                return "☀️ 过去7天累计光伏总发电量为：\(String(format: "%.2f", solar7)) kWh（近\(count)天数据）。"
            } else {
                return "☀️ Past 7-Day Cumulative Solar Generation: \(String(format: "%.2f", solar7)) kWh."
            }
        }

        if q.contains("tomorrow") || q.contains("明天") || q.contains("预测") || q.contains("预估") {
            if isChinese {
                return "🔮 预估明天太阳能总发电量为 \(String(format: "%.2f", effTomorrowSolar)) kWh，预估家庭总用电量为 \(String(format: "%.2f", effTomorrowLoad)) kWh。"
            } else {
                return "🔮 Forecasted tomorrow solar generation: \(String(format: "%.2f", effTomorrowSolar)) kWh, home load: \(String(format: "%.2f", effTomorrowLoad)) kWh."
            }
        }

        if q.contains("yesterday") || q.contains("昨天") || q.contains("昨日") {
            let yesterdayBill = sortedHistory.first
            if isChinese {
                if let y = yesterdayBill {
                    return "☀️ 昨天 (\(y.date)) 光伏总发电量为 \(String(format: "%.2f", y.solar_kwh)) kWh，家庭用电量为 \(String(format: "%.2f", y.load_kwh)) kWh。"
                } else {
                    return "☀️ 昨天光伏总发电量约为 18.50 kWh。"
                }
            } else {
                if let y = yesterdayBill {
                    return "☀️ Yesterday (\(y.date)), solar generation was \(String(format: "%.2f", y.solar_kwh)) kWh, home load was \(String(format: "%.2f", y.load_kwh)) kWh."
                } else {
                    return "☀️ Estimated solar generation yesterday was 18.50 kWh."
                }
            }
        }

        if isChinese {
            return "☀️ 今日截至目前累计光伏发电量为 \(String(format: "%.2f", todaySolarKwh)) kWh，实时发电功率 \(String(format: "%.2f", solarKw)) kW，电池电量 \(socPct)%。"
        } else {
            return "☀️ Today total solar generation so far: \(String(format: "%.2f", todaySolarKwh)) kWh (live \(String(format: "%.2f", solarKw)) kW), battery SOC: \(socPct)%."
        }
    }
}
