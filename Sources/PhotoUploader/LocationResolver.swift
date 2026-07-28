import Contacts
import CoreLocation
import Foundation

/// The best-effort results of reverse-geocoding a photo's GPS coordinates:
/// a street address, and — when the coordinates land on a named point of
/// interest — a business / map-entry name. Either can be nil; not every
/// coordinate resolves to a street address or a place.
struct ResolvedLocation: Equatable {
    var address: String?
    var business: String?
}

/// Turns raw GPS coordinates into human-readable place names via Apple's
/// online geocoder. This needs the network, so callers layer it on top of the
/// always-available raw coordinates rather than depending on it.
enum LocationResolver {
    /// Parses a "lat, lon" string (as produced by `ExifReader`) back into a
    /// coordinate. Returns nil if the string isn't a coordinate pair.
    static func coordinate(from location: String) -> CLLocationCoordinate2D? {
        let parts = location.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    static func resolve(coordinateString: String) async -> ResolvedLocation {
        guard let coord = coordinate(from: coordinateString) else { return ResolvedLocation() }
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks?.first else { return ResolvedLocation() }

        var result = ResolvedLocation()

        if let postal = placemark.postalAddress {
            let formatted = CNPostalAddressFormatter
                .string(from: postal, style: .mailingAddress)
                .split(separator: "\n")
                .joined(separator: ", ")
            if !formatted.isEmpty { result.address = formatted }
        }

        // Prefer an explicit area of interest ("Golden Gate Park", "Apple
        // Park"). Otherwise fall back to the placemark's own name, but only
        // when it's a real place label rather than a restatement of the
        // street address we already captured.
        if let poi = placemark.areasOfInterest?.first, !poi.isEmpty {
            result.business = poi
        } else if let name = placemark.name, !name.isEmpty,
                  name != placemark.thoroughfare,
                  result.address?.hasPrefix(name) != true {
            result.business = name
        }

        return result
    }
}
