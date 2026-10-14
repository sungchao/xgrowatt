import Foundation

struct RealtimeCostResult {
    var netCost: Double = 0.0
    var importCost: Double = 0.0
    var exportCredit: Double = 0.0
    var savings: Double = 0.0
    var arbitrage: Double = 0.0
    var dailySupplyChargeProRated: Double = 0.0
    
    var costTrend: [CostTrendPoint] = []
}

struct CostTrendPoint: Identifiable {
    var id = UUID()
    var timestamp: Date
    var cumulativeNetCost: Double
    var cumulativeSavings: Double
}

class CostCalculator {
    
    static func rateForTime(date: Date, plan: ElectricityTariffPlan) -> (importRate: Double, exportRate: Double) {
        let calendar = Calendar.current
        let dayOfWeek = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let totalMinutes = hour * 60 + minute
        
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let dayStr = dayNames[dayOfWeek - 1]
        
        for rule in plan.rules {
            guard rule.enabled else { continue }
            if rule.days.contains(dayStr) {
                let startParts = rule.start_time.split(separator: ":").compactMap { Int($0) }
                let endParts = rule.end_time.split(separator: ":").compactMap { Int($0) }
                
                if startParts.count == 2 && endParts.count == 2 {
                    let startMinutes = startParts[0] * 60 + startParts[1]
                    let endMinutes = endParts[0] * 60 + endParts[1]
                    
                    if startMinutes < endMinutes {
                        if totalMinutes >= startMinutes && totalMinutes < endMinutes {
                            return (rule.import_rate, rule.export_rate)
                        }
                    } else {
                        if totalMinutes >= startMinutes || totalMinutes < endMinutes {
                            return (rule.import_rate, rule.export_rate)
                        }
                    }
                }
            }
        }
        
        return (plan.fallbackImportRate, plan.fallbackExportRate)
    }
    
    static func calculateRealtimeCost(history: [TelemetryEntry], plan: ElectricityTariffPlan) -> RealtimeCostResult {
        var result = RealtimeCostResult()
        guard history.count > 1 else { return result }
        
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let todayHistory = history.filter { entry in
            guard let ts = entry.timestamp else { return false }
            return ts >= todayStart
        }
        
        guard todayHistory.count > 1 else { return result }
        
        var runningCost = 0.0
        var runningCredit = 0.0
        var runningSavings = 0.0
        var runningArbitrage = 0.0
        var proRatedSupplyCharge = 0.0
        
        var trendPoints: [CostTrendPoint] = []
        
        if let first = todayHistory.first, let t0 = first.timestamp {
            trendPoints.append(CostTrendPoint(timestamp: t0, cumulativeNetCost: 0.0, cumulativeSavings: 0.0))
        }
        
        var minRate = plan.fallbackImportRate
        for rule in plan.rules {
            if rule.enabled {
                minRate = min(minRate, rule.import_rate)
            }
        }
        
        for i in 0..<(todayHistory.count - 1) {
            let e1 = todayHistory[i]
            let e2 = todayHistory[i+1]
            guard let t1 = e1.timestamp, let t2 = e2.timestamp else { continue }
            
            let dtHours = t2.timeIntervalSince(t1) / 3600.0
            if dtHours > 1.0 { continue }
            
            let importSeg = ((e1.grid_import_kw + e2.grid_import_kw) / 2.0) * dtHours
            let exportSeg = ((e1.grid_export_kw + e2.grid_export_kw) / 2.0) * dtHours
            let dischargeSeg = ((e1.discharge_power_kw + e2.discharge_power_kw) / 2.0) * dtHours
            
            let rates = rateForTime(date: t1, plan: plan)
            
            let costSeg = importSeg * rates.importRate
            let creditSeg = exportSeg * rates.exportRate
            
            runningCost += costSeg
            runningCredit += creditSeg
            
            let supplySeg = plan.dailySupplyCharge * (dtHours / 24.0)
            proRatedSupplyCharge += supplySeg
            
            let offsetPower = max(0.0, ((e1.local_load_kw + e2.local_load_kw)/2.0) - ((e1.grid_import_kw + e2.grid_import_kw)/2.0))
            let savingsSeg = offsetPower * dtHours * rates.importRate
            runningSavings += savingsSeg
            
            if rates.importRate > minRate {
                let arbitrageSeg = dischargeSeg * (rates.importRate - minRate)
                runningArbitrage += arbitrageSeg
            }
            
            let cumulativeNet = runningCost - runningCredit + proRatedSupplyCharge
            trendPoints.append(CostTrendPoint(
                timestamp: t2,
                cumulativeNetCost: cumulativeNet,
                cumulativeSavings: runningSavings
            ))
        }
        
        result.netCost = runningCost - runningCredit + proRatedSupplyCharge
        result.importCost = runningCost
        result.exportCredit = runningCredit
        result.savings = runningSavings
        result.arbitrage = runningArbitrage
        result.dailySupplyChargeProRated = proRatedSupplyCharge
        result.costTrend = trendPoints
        
        return result
    }
}
