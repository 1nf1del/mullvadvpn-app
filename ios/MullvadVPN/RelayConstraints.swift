//
//  RelayConstraint.swift
//  MullvadVPN
//
//  Created by pronebird on 10/06/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation

private let kRelayConditionAnyRepr = "any"

enum RelayCondition<T: Codable>: Codable {
    case any
    case only(T)

    private struct OnlyRepr: Codable {
        var only: T
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        let decoded = try? container.decode(String.self)
        if decoded == kRelayConditionAnyRepr {
            self = .any
        } else {
            let onlyVariant = try container.decode(OnlyRepr.self)

            self = .only(onlyVariant.only)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .any:
            try container.encode(kRelayConditionAnyRepr)
        case .only(let inner):
            try container.encode(OnlyRepr(only: inner))
        }
    }
}

enum RelayLocationConstraint: Codable, CustomStringConvertible {
    case country(String)
    case city(String, String)
    case hostname(String, String, String)

    var description: String {
        switch self {
        case .country(let country):
            return String(
                format: NSLocalizedString("%@", tableName: "RelayConstraint", comment: "Relay constraint description: {city}"),
                country.uppercased())

        case .city(let country, let city):
            return String(
                format: NSLocalizedString("%@, %@", tableName: "RelayConstraint", comment: "Relay constraint description: {city}, {country}"),
                city.uppercased(), country.uppercased())

        case .hostname(let country, let city, let host):
            return String(
                format: NSLocalizedString(
                    "%@, %@, hostname %@", tableName: "RelayConstraint", comment: ""),
                city.uppercased(), country.uppercased(), host)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        let components = try container.decode([String].self)

        switch components.count {
        case 1:
            self = .country(components[0])
        case 2:
            self = .city(components[0], components[1])
        case 3:
            self = .hostname(components[0], components[1], components[2])
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid enum representation")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .country(let code):
            try container.encode([code])

        case .city(let countryCode, let cityCode):
            try container.encode([countryCode, cityCode])

        case .hostname(let countryCode, let cityCode, let hostname):
            try container.encode([countryCode, cityCode, hostname])
        }
    }

}

struct RelayConstraints: Codable, CustomStringConvertible {
    var location: RelayCondition<RelayLocationConstraint> = .any

    var description: String {
        switch location {
        case .any:
            return NSLocalizedString("Any location", tableName: "RelayConstraint", comment: "Any relay location constraint description")
        case .only(let only):
            return "\(only)"
        }
    }

    static var `default`: RelayConstraints {
        return RelayConstraints(location: .any)
    }
}
