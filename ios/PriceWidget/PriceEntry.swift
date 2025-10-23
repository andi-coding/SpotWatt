import WidgetKit
import SwiftUI

// MARK: - Price Data Model
struct PriceData: Codable {
    let startTime: Date
    let endTime: Date
    let price: Double
}

// MARK: - Widget Timeline Entry
struct PriceEntry: TimelineEntry {
    let date: Date
    let currentPrice: Double
    let priceStatus: String
    let priceTrend: String
    let minPrice: Double
    let maxPrice: Double
    let minTime: String
    let maxTime: String
    let lastUpdate: String

    // Configuration info
    let configuration: WidgetConfiguration

    // Placeholder entry for widget preview
    static var placeholder: PriceEntry {
        PriceEntry(
            date: Date(),
            currentPrice: 12.5,
            priceStatus: "medium",
            priceTrend: "stable",
            minPrice: 8.2,
            maxPrice: 18.9,
            minTime: "03:00",
            maxTime: "19:00",
            lastUpdate: "15:30",
            configuration: WidgetConfiguration.default
        )
    }
}

// MARK: - Widget Configuration
struct WidgetConfiguration: Codable {
    let providerPercentage: Double
    let providerFixedFee: Double
    let networkCosts: Double
    let includeTax: Bool
    let region: String
    let themeMode: String
    let fullCostMode: Bool

    static var `default`: WidgetConfiguration {
        WidgetConfiguration(
            providerPercentage: 0.0,
            providerFixedFee: 0.0,
            networkCosts: 0.0,
            includeTax: true,
            region: "AT",
            themeMode: "system",
            fullCostMode: false
        )
    }

    var taxRate: Double {
        region == "AT" ? 1.20 : 1.19
    }
}
