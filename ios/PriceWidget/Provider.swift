import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {

    // MARK: - Timeline Provider Methods

    /// Placeholder entry shown in widget gallery
    func placeholder(in context: Context) -> PriceEntry {
        return PriceEntry.placeholder
    }

    /// Snapshot for widget preview (e.g., in widget gallery)
    func getSnapshot(in context: Context, completion: @escaping (PriceEntry) -> Void) {
        // For preview, try to load real data, fall back to placeholder
        Task {
            if let entry = await loadCurrentEntry() {
                completion(entry)
            } else {
                completion(PriceEntry.placeholder)
            }
        }
    }

    /// Main timeline generation - called when widget needs to update
    func getTimeline(in context: Context, completion: @escaping (Timeline<PriceEntry>) -> Void) {
        Task {
            await generateTimeline(completion: completion)
        }
    }

    // MARK: - Timeline Generation

    /// Generate timeline with entries for next 24-48 hours
    private func generateTimeline(completion: @escaping (Timeline<PriceEntry>) -> Void) async {
        print("[Provider] Generating timeline...")

        // 1. Load configuration from App Group
        guard let config = loadConfiguration() else {
            print("[Provider] ⚠️ Failed to load configuration, using placeholder")
            let entry = PriceEntry.placeholder
            let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
            completion(timeline)
            return
        }

        // 2. Fetch prices from Cloudflare Worker
        do {
            let prices = try await CloudflarePriceService.fetchPricesWithFullCost(config: config)
            print("[Provider] ✅ Loaded \(prices.count) prices")

            // 3. Generate timeline entries
            let entries = generateEntries(from: prices, config: config)
            print("[Provider] ✅ Generated \(entries.count) timeline entries")

            // 4. Calculate next reload time
            let nextReload = calculateNextReloadDate()
            print("[Provider] 📅 Next reload scheduled for: \(nextReload)")

            // 5. Create and return timeline
            let timeline = Timeline(entries: entries, policy: .after(nextReload))
            completion(timeline)

        } catch {
            print("[Provider] ❌ Error fetching prices: \(error)")

            // Fallback: return placeholder with retry in 15 minutes
            let entry = PriceEntry.placeholder
            let retryDate = Date().addingTimeInterval(15 * 60)
            let timeline = Timeline(entries: [entry], policy: .after(retryDate))
            completion(timeline)
        }
    }

    // MARK: - Entry Generation

    /// Generate timeline entries for each hour
    private func generateEntries(from prices: [PriceData], config: WidgetConfiguration) -> [PriceEntry] {
        var entries: [PriceEntry] = []
        let now = Date()
        let calendar = Calendar.current

        // Get all prices as array for calculations
        let priceValues = prices.map { $0.price }

        // Generate entries for next 48 hours (or until we run out of price data)
        let endTime = now.addingTimeInterval(48 * 3600)

        // Round to next hour
        let startHour = calendar.date(bySetting: .minute, value: 0, of: now.addingTimeInterval(3600))!

        var currentDate = startHour
        while currentDate < endTime {
            // Find price for this hour
            guard let priceData = prices.first(where: { price in
                price.startTime <= currentDate && price.endTime > currentDate
            }) else {
                // No more price data available, stop generating entries
                break
            }

            // Calculate status and trend
            let status = PriceCalculator.getPriceStatus(current: priceData.price, prices: priceValues)
            let trend = PriceCalculator.getPriceTrend(prices: prices, now: currentDate)

            // Get min/max for today
            let minInfo = PriceCalculator.getMinPrice(prices, targetDay: currentDate) ?? (0, "00:00")
            let maxInfo = PriceCalculator.getMaxPrice(prices, targetDay: currentDate) ?? (0, "00:00")

            // Create entry
            let entry = PriceEntry(
                date: currentDate,
                currentPrice: priceData.price,
                priceStatus: status,
                priceTrend: trend,
                minPrice: minInfo.price,
                maxPrice: maxInfo.price,
                minTime: minInfo.time,
                maxTime: maxInfo.time,
                lastUpdate: PriceCalculator.formatTime(Date()),
                configuration: config
            )

            entries.append(entry)

            // Move to next hour
            currentDate = calendar.date(byAdding: .hour, value: 1, to: currentDate)!
        }

        return entries
    }

    // MARK: - Configuration Loading

    /// Load widget configuration from App Group (shared with Flutter app)
    private func loadConfiguration() -> WidgetConfiguration? {
        guard let userDefaults = UserDefaults(suiteName: "group.com.spotwatt.app") else {
            print("[Provider] ⚠️ Failed to access App Group")
            return nil
        }

        let config = WidgetConfiguration(
            providerPercentage: userDefaults.double(forKey: "energy_provider_percentage"),
            providerFixedFee: userDefaults.double(forKey: "energy_provider_fixed_fee"),
            networkCosts: userDefaults.double(forKey: "network_costs"),
            includeTax: userDefaults.bool(forKey: "include_tax"),
            region: userDefaults.string(forKey: "region") ?? "AT",
            themeMode: userDefaults.string(forKey: "theme_mode") ?? "system",
            fullCostMode: userDefaults.bool(forKey: "full_cost_mode")
        )

        print("[Provider] 📋 Loaded config: region=\(config.region), fullCost=\(config.fullCostMode)")
        return config
    }

    // MARK: - Reload Schedule

    /// Calculate next reload date
    /// Strategy: Reload at 17:30 to get fresh prices for tomorrow
    /// (Cloudflare Worker receives new prices between 14:00-17:00)
    private func calculateNextReloadDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)

        // If before 17:30, schedule for today at 17:30
        // If after 17:30, schedule for tomorrow at 17:30
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 17
        components.minute = 30

        if currentHour >= 17 {
            // After 17:30 - schedule for tomorrow
            components.day! += 1
        }

        return calendar.date(from: components) ?? now.addingTimeInterval(3600)
    }

    // MARK: - Helpers

    /// Load current entry (for snapshot)
    private func loadCurrentEntry() async -> PriceEntry? {
        guard let config = loadConfiguration() else {
            return nil
        }

        do {
            let prices = try await CloudflarePriceService.fetchPricesWithFullCost(config: config)
            let entries = generateEntries(from: prices, config: config)
            return entries.first
        } catch {
            return nil
        }
    }
}
