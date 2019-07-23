//
//  NETunnelProviderManagerProcedures.swift
//  MullvadVPN
//
//  Created by pronebird on 23/07/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import NetworkExtension
import ProcedureKit

/// A procedure that loads the NETunnelProviderManagers from preferences
class LoadTunnelProviderManagersProcedure: Procedure, OutputProcedure {
    var output: Pending<ProcedureResult<[NETunnelProviderManager]>> = .pending

    override func execute() {
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            if let error = error {
                self.finish(withResult: .failure(error))
            } else {
                self.finish(withResult: .success(managers ?? []))
            }
        }
    }
}

/// A procedure that saves the changes to the given NETunnelProviderManager to preferences
class SaveTunnelProviderManagerProcedure: Procedure, InputProcedure {
    var input: Pending<NETunnelProviderManager>

    init(tunnelManager: NETunnelProviderManager? = nil) {
        self.input = tunnelManager.flatMap { .ready($0) } ?? .pending
        super.init()
    }

    override func execute() {
        guard let tunnelManager = input.value else {
            finish(with: ProcedureKitError.requirementNotSatisfied())
            return
        }

        tunnelManager.saveToPreferences(completionHandler: { (error) in
            if let error = error {
                self.finish(with: error)
            } else {
                self.finish()
            }
        })
    }

}
