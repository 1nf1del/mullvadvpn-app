//
//  ConnectViewController.swift
//  MullvadVPN
//
//  Created by pronebird on 20/03/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import UIKit
import NetworkExtension
import os

class ConnectViewController: UIViewController, RootContainment {

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    var preferredHeaderBarStyle: HeaderBarStyle {
        return .unsecured
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    // MARK: - Actions

    @IBAction func unwindFromSelectLocation(segue: UIStoryboardSegue) {
        guard let selectLocationController = segue.source as? SelectLocationController else { return }
        guard let selectedItem = selectLocationController.selectedItem else { return }

        let relayLocationConstraint = selectedItem.intoRelayLocationConstraint()
        let relayConstraints = RelayConstraints(location: .only(relayLocationConstraint))

        try? TunnelConfigurationInteractor.updateRelayConstraints(relayConstraints)
    }

}
