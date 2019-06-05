//
//  RelayListCache.swift
//  MullvadVPN
//
//  Created by pronebird on 05/06/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import ProcedureKit
import os.log

/// A struct that represents the relays cache on disk
struct RelayListCache: Codable {
    /// The relay list stored within the cache entry
    var relayList: RelayList

    /// The date when this cache was last updated
    var updatedAt: Date

    /// Returns true if it's time to refresh the relay list cache
    func needsUpdate() -> Bool {
        let now = Date()
        guard let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: updatedAt) else {
            return false
        }

        return now >= nextUpdate
    }

    /// Error emitted by read and write functions
    enum Error: Swift.Error {
        case io(Swift.Error)
        case coding(Swift.Error)
    }

    /// The default cache file location
    static var defaultCacheFileURL: URL? {
        let appGroupIdentifier = ApplicationConfiguration.securityGroupIdentifier
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)

        return containerURL.flatMap { URL(fileURLWithPath: "relays.json", relativeTo: $0) }
    }

    /// Safely read the cache file from disk using file coordinator
    static func read(cacheFileURL: URL, completion: @escaping (Result<RelayListCache, Error>) -> Void) {
        let fileCoordinator = NSFileCoordinator(filePresenter: nil)

        let accessor = { (fileURLForReading: URL) -> Void in
            var data: Data

            // Read data from disk
            do {
                data = try Data(contentsOf: fileURLForReading)
            } catch {
                completion(.failure(.io(error)))
                return
            }

            // Decode data into RelayListCacheFile
            do {
                let decoded = try JSONDecoder().decode(RelayListCache.self, from: data)

                completion(.success(decoded))
            } catch {
                completion(.failure(.coding(error)))
            }
        }

        var error: NSError?
        fileCoordinator.coordinate(readingItemAt: cacheFileURL,
                                   options: [.withoutChanges],
                                   error: &error,
                                   byAccessor: accessor)

        if let error = error {
            completion(.failure(.io(error)))
        }
    }

    /// Safely write the cache file on disk using file coordinator
    static func write(cacheFileURL: URL, entry: RelayListCache, completion: @escaping (Result<Void, Error>) -> Void) {
        let fileCoordinator = NSFileCoordinator(filePresenter: nil)

        let accessor = { (fileURLForWriting: URL) -> Void in
            var data: Data

            // Encode data
            do {
                data = try JSONEncoder().encode(entry)
            } catch {
                completion(.failure(.coding(error)))
                return
            }

            // Write data
            do {
                try data.write(to: fileURLForWriting)

                completion(.success(()))
            } catch {
                completion(.failure(.io(error)))
            }
        }

        var error: NSError?
        fileCoordinator.coordinate(writingItemAt: cacheFileURL,
                                   options: [.forReplacing],
                                   error: &error,
                                   byAccessor: accessor)

        if let error = error {
            completion(.failure(.io(error)))
        }
    }
}
