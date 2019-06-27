//
//  Account.swift
//  MullvadVPN
//
//  Created by pronebird on 16/05/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import ProcedureKit
import os

/// A class that groups the account related operations
class Account {

    enum Error: Swift.Error {
        case invalidAccount
    }

    /// Returns the currently used account token
    static var token: String? {
        return UserDefaultsInteractor.sharedApplicationGroupInteractor.accountToken
    }

    /// Returns the account expiry for the currently used account token
    static var expiry: Date? {
        return UserDefaultsInteractor.sharedApplicationGroupInteractor.accountExpiry
    }

    static var isLoggedIn: Bool {
        return token != nil
    }

    /// Perform the login and save the account token along with expiry (if available) to the
    /// application preferences.
    class func login(with accountToken: String) -> Procedure {
        // Request account token verification
        let verificationProcedure = AccountVerificationProcedure(accountToken: accountToken)

        // Update the application preferences based on the AccountVerification result.
        let saveAccountDataProcedure = TransformProcedure { (verification) in
            try self.handleVerification(verification, for: accountToken)
        }.injectResult(from: verificationProcedure)

        return GroupProcedure(operations: [verificationProcedure, saveAccountDataProcedure])
    }

    /// Perform the logout by erasing the account token and expiry from the application preferences.
    class func logout() {
        let userDefaultsInteractor = UserDefaultsInteractor.sharedApplicationGroupInteractor

        userDefaultsInteractor.accountToken = nil
        userDefaultsInteractor.accountExpiry = nil
    }

    private class func handleVerification(_ verification: AccountVerification, for accountToken: String) throws {
        switch verification {
        case .verified(let expiry):
            try self.setupAccount(accountToken: accountToken, expiry: expiry)

        case .deferred(let error):
            try self.setupAccount(accountToken: accountToken)

            os_log(.info, #"Could not request the account verification "%{private}s": %{public}s"#,
                   accountToken, error.localizedDescription)

        case .invalid:
            throw Error.invalidAccount
        }
    }

    private class func setupAccount(accountToken: String, expiry: Date? = nil) throws {
        let userDefaultsInteractor = UserDefaultsInteractor.sharedApplicationGroupInteractor

        let tunnelConfig = (
            try? TunnelConfigurationManager.shared
                .getConfiguration(for: accountToken)
            ) ?? TunnelConfiguration.default(with: accountToken)

        _ = try TunnelConfigurationManager.shared.saveConfiguration(tunnelConfig)

        // Save the account token and expiry into preferences
        userDefaultsInteractor.accountToken = accountToken
        userDefaultsInteractor.accountExpiry = expiry
    }

}

