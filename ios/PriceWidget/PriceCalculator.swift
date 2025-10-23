import Foundation

class PriceCalculator {

    // MARK: - Full Cost Calculation

    /// Calculate full cost from SPOT price (NETTO)
    /// Formula: SpotBrutto + ProviderFeeBrutto + NetworkCostsBrutto
    static func calculateFullCost(
        spotNetto: Double,
        config: WidgetConfiguration
    ) -> Double {
        guard config.fullCostMode else {
            return spotNetto
        }

        // 1. SPOT NETTO → BRUTTO (apply tax)
        let spotBrutto = spotNetto * config.taxRate

        // 2. Provider Fee (BRUTTO, uses absolute value of spot)
        let providerFeeBrutto = abs(spotNetto) * (config.providerPercentage / 100.0) + config.providerFixedFee

        // 3. Network Costs (BRUTTO)
        let networkCostsBrutto = config.includeTax
            ? config.networkCosts
            : config.networkCosts * config.taxRate

        // 4. Sum all BRUTTO values
        return spotBrutto + providerFeeBrutto + networkCostsBrutto
    }

    // MARK: - Price Status (Median-based)

    /// Calculate price status: "low", "medium", "high"
    /// Based on median ±15% thresholds
    static func getPriceStatus(current: Double, prices: [Double]) -> String {
        guard !prices.isEmpty else { return "medium" }

        let sorted = prices.sorted()
        let medianIndex = sorted.count / 2  // floor division
        let median = sorted[medianIndex]

        let range15 = median * 0.15
        let greenThreshold = median - range15   // Median - 15%
        let orangeThreshold = median + range15  // Median + 15%

        if current < greenThreshold {
            return "low"      // < Median - 15%
        } else if current < orangeThreshold {
            return "medium"   // Median ± 15%
        } else {
            return "high"     // > Median + 15%
        }
    }

    // MARK: - 3H-Trend Calculation

    /// Calculate 3-hour price trend
    /// Returns: "stable", "slightly_rising", "slightly_falling", "strongly_rising", "strongly_falling"
    static func getPriceTrend(prices: [PriceData], now: Date) -> String {
        // Get current price
        guard let currentPrice = getCurrentPrice(prices, now: now) else {
            return "stable"
        }

        // Get all prices for today (00:00 - 23:59)
        let fullTodayPrices = getFullDayPrices(prices, targetDay: now)
        guard !fullTodayPrices.isEmpty else {
            return "stable"
        }

        // Calculate today's min and max
        let todayMin = fullTodayPrices.map { $0.price }.min()!
        let todayMax = fullTodayPrices.map { $0.price }.max()!
        let todayRange = todayMax - todayMin

        // Get next 3 hours
        let next3Hours = now.addingTimeInterval(3 * 3600)
        let nextHours = prices.filter { price in
            price.startTime > now && price.startTime < next3Hours
        }.sorted { $0.startTime < $1.startTime }

        guard !nextHours.isEmpty else {
            return "stable"
        }

        // Calculate weighted average (60%, 25%, 15%)
        let weightedAvg: Double
        if nextHours.count == 1 {
            weightedAvg = nextHours[0].price
        } else if nextHours.count == 2 {
            weightedAvg = nextHours[0].price * 0.7 + nextHours[1].price * 0.3
        } else {
            weightedAvg = nextHours[0].price * 0.6 +
                         nextHours[1].price * 0.25 +
                         nextHours[2].price * 0.15
        }

        // Small range check - if day range < 0.5 ct, everything is stable
        if todayRange < 0.5 {
            return "stable"
        }

        // Calculate relative change in context of day's range
        let currentPosition = (currentPrice.price - todayMin) / todayRange
        let futurePosition = (weightedAvg - todayMin) / todayRange
        let relativeChange = (futurePosition - currentPosition) * 100  // % of day's range

        let absRelativeChange = abs(relativeChange)

        // Determine trend based on thresholds
        if absRelativeChange < 5 {
            return "stable"
        } else if absRelativeChange <= 20 {
            return relativeChange > 0 ? "slightly_rising" : "slightly_falling"
        } else {
            return relativeChange > 0 ? "strongly_rising" : "strongly_falling"
        }
    }

    // MARK: - Helper Functions

    /// Get current price (now between startTime and endTime)
    static func getCurrentPrice(_ prices: [PriceData], now: Date) -> PriceData? {
        return prices.first { price in
            price.startTime <= now && price.endTime > now
        }
    }

    /// Get all prices for a specific day (00:00 - 23:59)
    static func getFullDayPrices(_ prices: [PriceData], targetDay: Date) -> [PriceData] {
        let calendar = Calendar.current
        return prices.filter { price in
            calendar.isDate(price.startTime, inSameDayAs: targetDay)
        }
    }

    /// Get min price info for today
    static func getMinPrice(_ prices: [PriceData], targetDay: Date) -> (price: Double, time: String)? {
        let todayPrices = getFullDayPrices(prices, targetDay: targetDay)
        guard let minPrice = todayPrices.min(by: { $0.price < $1.price }) else {
            return nil
        }
        return (minPrice.price, formatTime(minPrice.startTime))
    }

    /// Get max price info for today
    static func getMaxPrice(_ prices: [PriceData], targetDay: Date) -> (price: Double, time: String)? {
        let todayPrices = getFullDayPrices(prices, targetDay: targetDay)
        guard let maxPrice = todayPrices.max(by: { $0.price < $1.price }) else {
            return nil
        }
        return (maxPrice.price, formatTime(maxPrice.startTime))
    }

    /// Format time as HH:mm
    static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
