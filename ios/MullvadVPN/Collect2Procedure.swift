//
//  Collect2Procedure.swift
//  MullvadVPN
//
//  Created by pronebird on 23/07/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import ProcedureKit

/// A procedure that collects the output of two given procedures into a tuple
class Collect2Procedure<A, B>: GroupProcedure, OutputProcedure
where A: Operation & OutputProcedure, B: Operation & OutputProcedure {

    var output: Pending<ProcedureResult<(A.Output, B.Output)>> = .pending

    init(dispatchQueue underlyingQueue: DispatchQueue? = nil, from operationA: A, and operationB: B) {
        let transformer = TransformProcedure { [weak operationA, weak operationB] () -> Output in
            guard let output1 = operationA?.output.success,
                let output2 = operationB?.output.success else {
                    throw ProcedureKitError.requirementNotSatisfied()
            }
            return (output1, output2)
        }

        transformer.addDependencies(operationA, operationB)

        super.init(dispatchQueue: underlyingQueue, operations: [operationA, operationB, transformer])

        // assign the output from transformer
        bind(from: transformer)
    }
}
