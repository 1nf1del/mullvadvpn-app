//
//  RelaySelector.swift
//  PacketTunnel
//
//  Created by pronebird on 11/06/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation

class RelaySelector {

    private let relayList: RelayList

    init(relayList: RelayList) {
        self.relayList = relayList
    }

    class func loadedFromRelayCache(completion: @escaping (Result<RelaySelector, Error>) -> Void) {
        let cacheFileURL = RelayListCache.defaultCacheFileURL!

        RelayListCache.read(cacheFileURL: cacheFileURL) { (result) in
            switch result {
            case .success(let cache):
                completion(.success(RelaySelector(relayList: cache.relayList)))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func evaluate(with constraint: RelayConstraint) -> RelayList.WireguardTunnel? {
        // Stub implementation

        for country in relayList.countries {
            for city in country.cities {
                for relay in city.relays {
                    guard let tunnels = relay.tunnels, let wireguardTunnels = tunnels.wireguard else {
                        continue
                    }

                    for wireguardTunnel in wireguardTunnels {
                        return wireguardTunnel
                    }
                }
            }
        }

        return nil
    }

}

