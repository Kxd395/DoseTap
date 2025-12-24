import Foundation

struct DashboardConfig: Codable {
    struct Filters: Codable {
        let date_range: [String]?
        let source: [String]?
        let metric: [String]?
    }
    struct Visualization: Codable {
        let merged_view: Bool?
        let comparison_supported: Bool?
        let error_messages: [String]?
    }
    let display_order: String?
    let filters: Filters?
    let visualization: Visualization?
}

extension DataSource {
    static func from(_ s: String) -> DataSource? { DataSource(rawValue: s) }
}

extension DataMetric {
    static func from(_ s: String) -> DataMetric? { DataMetric(rawValue: s) }
}

