//
//  ProcedureKit+Patches.swift
//  MullvadVPN
//
//  Created by pronebird on 10/06/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import ProcedureKit

extension InputProcedure {

    /// The original implementation of bind(to: T) has a bug
    /// This is an attempt to temporarily patch it.
    /// Github issue: https://github.com/ProcedureKit/ProcedureKit/issues/936
    func bindAndNotifySetInputReady<T: InputProcedure>(to target: T) where T.Input == Self.Input {
        addDidSetInputReadyBlockObserver { (procedure) in
            if case .ready = procedure.input {
                target.input = procedure.input
                target.didSetInputReady()
            }
        }
    }
}
