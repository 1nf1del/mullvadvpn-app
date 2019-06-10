//
//  PacketTunnelProvider.swift
//  PacketTunnel
//
//  Created by pronebird on 19/03/2019.
//  Copyright © 2019 Amagicom AB. All rights reserved.
//

import Foundation
import Network
import NetworkExtension
import ProcedureKit
import os.log

enum PacketTunnelProviderError: Error {
    case invalidProtocolConfiguration
    case setNetworkSettings
    case fileDescriptorNotFound
    case startWireGuardBackend
}

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var handle: Int32?
    private var networkMonitor: NWPathMonitor {
        let networkMonitor = NWPathMonitor()
        networkMonitor.pathUpdateHandler = { [weak self] in self?.didReceiveNetworkPathUpdate(path: $0) }
        return networkMonitor
    }
    private let networkMonitorQueue = DispatchQueue(label: "NetworkMonitor")
    private var lastSeenInterfaces: [String] = []
    private var tunnelInterfaceName: String?

    deinit {
        networkMonitor.cancel()
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        os_log(.info, "Starting the tunnel")

        guard let tunnelProviderProtocol = protocolConfiguration as? NETunnelProviderProtocol else {
            os_log(.error, "Failed to start the tunnel because of invalid protocol configuration")
            completionHandler(PacketTunnelProviderError.invalidProtocolConfiguration)
            return
        }

        // TODO: do something with relay constraint
        let tunnelConfiguration = TunnelConfiguration(with: tunnelProviderProtocol)

        let dnsSettings = NEDNSSettings(servers: ["10.0.0.1"])
        // All DNS queries must first go through the tunnel's DNS
        dnsSettings.matchDomains = [""]

        let tunnelNetworkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        tunnelNetworkSettings.dnsSettings = dnsSettings
        tunnelNetworkSettings.mtu = 1280

        setTunnelNetworkSettings(tunnelNetworkSettings) { (error) in
            if let error = error {
                os_log(.error, "Cannot set network settings: %{public}s", error.localizedDescription)

                completionHandler(PacketTunnelProviderError.setNetworkSettings)
            } else {
                self.networkMonitor.start(queue: self.networkMonitorQueue)

                let fileDescriptor = self.getTunnelInterfaceDescriptor()
                if fileDescriptor < 0 {
                    os_log(.error, "Cannot find the file descriptor for socket.")
                    completionHandler(PacketTunnelProviderError.fileDescriptorNotFound)
                    return
                }

                self.tunnelInterfaceName = self.getInterfaceName(fileDescriptor)

                os_log(.info, "Tunnel interface is %{public}s", self.tunnelInterfaceName ?? "unknown")

                // TODO: Generate configuration
//                let handle = wgTurnOn(gostring_t, fileDescriptor)
                let handle: Int32 = 0
                if handle < 0 {
                    os_log(.error, "Failed to start the Wireguard backend, wgTurnOn returned %{public}d", handle)

                    completionHandler(PacketTunnelProviderError.startWireGuardBackend)
                    return
                }

                self.handle = handle

                completionHandler(nil)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        os_log(.info, "Stopping the tunnel")

        networkMonitor.cancel()

        if let handle = self.handle {
            wgTurnOff(handle)
        }

        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Add code here to handle the message.
        if let handler = completionHandler {
            handler(messageData)
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        // Add code here to get ready to sleep.
        completionHandler()
    }

    override func wake() {
        // Add code here to wake up.
    }
}

extension PacketTunnelProvider {

    private func didReceiveNetworkPathUpdate(path: Network.NWPath) {
        guard let handle = self.handle, let tunnelInterfaceName = self.tunnelInterfaceName else {
            return
        }

        os_log(.debug,
               "Network change detected with %{public}s route and interface order %s",
               path.status.debugDescription,
               path.availableInterfaces.debugDescription)

        guard path.status == .satisfied else { return }

        // TODO: Update configuration
        // wgSetConfig(handle, $0)

        let interfaces = path.availableInterfaces.compactMap { (interface) -> String? in
            if interface.name == tunnelInterfaceName {
                return nil
            } else {
                return interface.name
            }
        }

        if !interfaces.elementsEqual(lastSeenInterfaces) {
            lastSeenInterfaces = interfaces
            wgBumpSockets(handle)
        }
    }

}


extension PacketTunnelProvider {

    fileprivate func getTunnelInterfaceDescriptor() -> Int32 {
        return packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 ?? -1
    }

    fileprivate func getInterfaceName(_ fileDescriptor: Int32) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(IFNAMSIZ))

        return buffer.withUnsafeMutableBufferPointer({ (mutableBufferPointer) -> String? in
            guard let baseAddress = mutableBufferPointer.baseAddress else { return nil }

            var ifnameSize = socklen_t(IFNAMSIZ)
            let result = getsockopt(
                fileDescriptor,
                2 /* SYSPROTO_CONTROL */,
                2 /* UTUN_OPT_IFNAME */,
                baseAddress,
                &ifnameSize)

            if result == 0 {
                return String(cString: baseAddress)
            } else {
                return nil
            }
        })
    }

}

extension Network.NWPath.Status: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .requiresConnection:
            return "requiresConnection"
        case .satisfied:
            return "satisfied"
        case .unsatisfied:
            return "unsatisfied"
        @unknown default:
            return "unknown"
        }
    }
}

extension String {
    func withGoString<T>(_ body: (gostring_t) -> T) -> T {
        return withCString { body(gostring_t(p: $0, n: self.utf8.count)) }
    }
}
