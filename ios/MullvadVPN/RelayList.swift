
//
//  RelayList.swift
//  MullvadVPN
//
//  Created by pronebird on 02/05/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation

struct RelayList: Codable {
    struct Country: Codable {
        let name: String
        let code: String
        let cities: [City]
    }

    struct City: Codable {
        let name: String
        let code: String
        let latitude: Double
        let longitude: Double
        let relays: [Hostname]
    }

    struct Hostname: Codable {
        let hostname: String
        let ipv4AddrIn: String
        let includeInCountry: Bool
        let weight: Int32
    }

    let countries: [Country]
}
