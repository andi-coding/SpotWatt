import WidgetKit
import SwiftUI

@main
struct PriceWidget: Widget {
    let kind: String = "PriceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PriceWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("SpotWatt Preis")
        .description("Zeigt den aktuellen Strompreis und 3h-Trend")
        .supportedFamilies([.systemMedium])
    }
}
