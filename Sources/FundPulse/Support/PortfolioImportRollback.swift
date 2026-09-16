import Foundation

/// Written before either import destination changes. Presence means the next
/// load must restore the pair; removal is the import's commit marker.
struct PortfolioImportRollback: Codable {
    var portfolio: PortfolioSnapshot
    var performance: PortfolioPerformanceSnapshot
}
