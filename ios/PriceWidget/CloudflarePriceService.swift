import Foundation

// MARK: - API Response Models
struct CloudflareAPIResponse: Codable {
    let prices: [CloudflarePriceData]
}

struct CloudflarePriceData: Codable {
    let start_timestamp: Int64
    let end_timestamp: Int64
    let marketprice: Double  // Price in €/MWh × 10
}

// MARK: - Cloudflare Price Service
class CloudflarePriceService {

    static let baseURL = "https://spotwatt-worker.andisandbox.workers.dev"

    /// Fetch prices from Cloudflare Worker
    /// Returns SPOT prices (NETTO) from API
    static func fetchPrices(region: String) async throws -> [PriceData] {
        let urlString = "\(baseURL)/api/prices?market=\(region)"

        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        print("[CloudflareService] Fetching prices for region: \(region)")

        // Make API call with 10 second timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        // Parse JSON
        let decoder = JSONDecoder()
        let apiResponse = try decoder.decode(CloudflareAPIResponse.self, from: data)

        print("[CloudflareService] Received \(apiResponse.prices.count) prices")

        // Convert to PriceData
        let prices = apiResponse.prices.map { cloudflarePrice in
            PriceData(
                startTime: Date(timeIntervalSince1970: TimeInterval(cloudflarePrice.start_timestamp / 1000)),
                endTime: Date(timeIntervalSince1970: TimeInterval(cloudflarePrice.end_timestamp / 1000)),
                price: cloudflarePrice.marketprice / 10.0  // Convert €/MWh×10 to ct/kWh
            )
        }

        return prices
    }

    /// Fetch prices and apply full cost calculation
    static func fetchPricesWithFullCost(config: WidgetConfiguration) async throws -> [PriceData] {
        // 1. Fetch raw SPOT prices from API
        let spotPrices = try await fetchPrices(region: config.region)

        // 2. Apply full cost calculation if enabled
        guard config.fullCostMode else {
            return spotPrices
        }

        print("[CloudflareService] Calculating full cost for \(spotPrices.count) prices")

        let fullCostPrices = spotPrices.map { spotPrice in
            let fullCost = PriceCalculator.calculateFullCost(
                spotNetto: spotPrice.price,
                config: config
            )
            return PriceData(
                startTime: spotPrice.startTime,
                endTime: spotPrice.endTime,
                price: fullCost
            )
        }

        return fullCostPrices
    }
}

// MARK: - API Errors
enum APIError: Error {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case noData
    case decodingError

    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .noData:
            return "No data received"
        case .decodingError:
            return "Failed to decode response"
        }
    }
}
