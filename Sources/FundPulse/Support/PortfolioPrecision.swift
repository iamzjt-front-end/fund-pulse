import Foundation

enum PortfolioPrecision {
    static let storedSharePlaces = 6
    static let displayedSharePlaces = 2
    static let shareAvailabilityTolerance = 0.5 / pow(10, Double(displayedSharePlaces))
    static let costPlaces = 4
    static let moneyPlaces = 2
}
