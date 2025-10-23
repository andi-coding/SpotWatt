import SwiftUI
import WidgetKit

struct PriceWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        ZStack {
            // Background
            Color.white

            VStack(alignment: .leading, spacing: 8) {
                // Header with Logo and Title
                HStack {
                    Spacer()
                    Text("SpotWatt")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.2, green: 0.7, blue: 0.9))
                }

                // "AKTUELL" Label
                Text("AKTUELL")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                    .kerning(0.5)

                // Current Price with Icon and Status
                HStack(alignment: .center, spacing: 8) {
                    // Price Status Icon
                    Text(getStatusIcon(entry.priceStatus))
                        .font(.system(size: 22))

                    // Current Price
                    Text(formatPrice(entry.currentPrice))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)

                    Spacer()

                    // Status Icon (right)
                    Text(getStatusEmoji(entry.priceStatus))
                        .font(.system(size: 16))
                }

                // Trend Section
                HStack(alignment: .center, spacing: 8) {
                    Text("3H-TREND:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                        .kerning(0.5)

                    Text(getTrendIcon(entry.priceTrend))
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(Color(red: 0.13, green: 0.13, blue: 0.13))
                        .minimumScaleFactor(0.6)

                    Spacer()

                    // Update Time
                    Text(entry.lastUpdate)
                        .font(.system(size: 10))
                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))

                    // Refresh Icon
                    Text("🔄")
                        .font(.system(size: 14))
                }
            }
            .padding(12)
        }
        .cornerRadius(16)
    }

    // MARK: - Helper Functions

    private func formatPrice(_ price: Double) -> String {
        // Handle -0.00 display issue
        let rounded = String(format: "%.2f", price)
        if rounded == "-0.00" {
            return "0.00 ct/kWh"
        }
        return "\(rounded) ct/kWh"
    }

    private func getStatusIcon(_ status: String) -> String {
        switch status {
        case "low":
            return "⚡"  // Green - cheap
        case "medium":
            return "○"  // Orange - medium
        case "high":
            return "⚠️"  // Red - expensive
        default:
            return "○"
        }
    }

    private func getStatusEmoji(_ status: String) -> String {
        switch status {
        case "low":
            return "💚"
        case "medium":
            return "🟠"
        case "high":
            return "🔴"
        default:
            return "🟠"
        }
    }

    private func getTrendIcon(_ trend: String) -> String {
        switch trend {
        case "stable":
            return "→"
        case "slightly_rising":
            return "↗"
        case "slightly_falling":
            return "↘"
        case "strongly_rising":
            return "⬆"
        case "strongly_falling":
            return "⬇"
        default:
            return "→"
        }
    }
}

// MARK: - Widget Preview
struct PriceWidget_Previews: PreviewProvider {
    static var previews: some View {
        PriceWidgetEntryView(entry: PriceEntry.placeholder)
            .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}
