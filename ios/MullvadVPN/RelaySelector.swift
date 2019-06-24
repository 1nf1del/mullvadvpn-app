//
//  RelaySelector.swift
//  PacketTunnel
//
//  Created by pronebird on 11/06/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import Network
import os

class RelaySelector {

    private let relayList: RelayList

    init(relayList: RelayList) {
        self.relayList = relayList
    }

    class func loadedFromRelayCache(completion: @escaping (Result<RelaySelector, Error>) -> Void) {
        do {
            let relayCache = try RelayCache.withDefaultLocation()

            relayCache.read { (result) in
                switch result {
                case .success(let cache):
                    completion(.success(RelaySelector(relayList: cache.relayList)))

                case .failure(let error):
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    func evaluate(with constraints: RelayConstraints) -> MullvadEndpoint? {
        // Stub implementation

        for country in relayList.countries {
            for city in country.cities {
                for relay in city.relays {
                    guard let tunnels = relay.tunnels, let wireguardTunnels = tunnels.wireguard else {
                        continue
                    }

                    for wireguardTunnel in wireguardTunnels {
                        guard let randomPort = wireguardTunnel.portRanges
                            .randomElement()? // random range
                            .randomElement() // random port
                            else { continue }

                        guard let networkPort = NWEndpoint.Port(rawValue: randomPort) else {
                            os_log("Couldn't convert %{public}d to NWEndpoint.Port", randomPort)
                            return nil
                        }

                        let ipv4Endpoint = NWEndpoint.hostPort(host: .ipv4(relay.ipv4AddrIn), port: networkPort)
                        // let ipv6Endpoint = NWEndpoint.hostPort(host: .ipv4(relay.ipv6AddrIn), port: randomPort)

                        return MullvadEndpoint(
                            ipv4Relay: ipv4Endpoint,
                            ipv6Relay: nil,
                            ipv4Gateway: wireguardTunnel.ipv4Gateway,
                            ipv6Gateway: wireguardTunnel.ipv6Gateway,
                            publicKey: wireguardTunnel.publicKey
                        )
                    }
                }
            }
        }

        return nil
    }

}

