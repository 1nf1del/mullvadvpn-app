//
//  ConnectViewController.swift
//  MullvadVPN
//
//  Created by pronebird on 20/03/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import UIKit
import NetworkExtension
import os.log

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

        let relayLocation = selectedItem.intoRelayLocation()
        let relayConstraint = RelayConstraint(location: .only(relayLocation))

        TunnelsManager.loadedFromPreferences { (result) in
            switch result {
            case .success(let tunnelsManager):
                let tunnel = tunnelsManager.tunnels.first
                    ?? NETunnelProviderManager.withPacketTunnelBundleIdentifier()
                tunnel.localizedDescription = "Wireguard"

                let protocolConfiguration = tunnel.protocolConfiguration as! NETunnelProviderProtocol
                protocolConfiguration.relayConstraint = relayConstraint
                protocolConfiguration.serverAddress = "\(relayConstraint)"

                tunnelsManager.addTunnel(tunnel, completion: { (result) in
                    switch result {
                    case .success:
                        os_log(.info, "Saved constraint")
                    case .failure(let error):
                        os_log(.error, "Failed to save the constraint: %s", error.localizedDescription)
                    }
                })

            case .failure(let error):
                os_log(.error, "Failed to load tunnels: %s", error.localizedDescription)
            }
        }
    }

}
