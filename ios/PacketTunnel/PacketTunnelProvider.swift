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
import os

enum PacketTunnelProviderError: Error {
    case readRelayCache
    case noRelaySatisfyingConstraint
    case invalidProtocolConfiguration
    case setNetworkSettings
    case fileDescriptorNotFound
    case startWireGuardBackend
}

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var handle: Int32?
    private var networkMonitor: NWPathMonitor?
    private let networkMonitorQueue = DispatchQueue(label: "NetworkMonitor")
    private var lastSeenInterfaces: [String] = []
    private var tunnelInterfaceName: String?

    private var packetTunnelSettingsGenerator: PacketTunnelSettingsGenerator?

    deinit {
        networkMonitor?.cancel()
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        os_log(.info, "Starting the tunnel")

        configureLogger()

        guard let tunnelProviderProtocol = protocolConfiguration as? NETunnelProviderProtocol,
            let tunnelConfiguration = tunnelProviderProtocol.asTunnelConfiguration() else {
                os_log(.error, "Failed to start the tunnel because of invalid protocol configuration")
                completionHandler(PacketTunnelProviderError.invalidProtocolConfiguration)
                return
        }

        RelaySelector.loadedFromRelayCache { (result) in
            switch result {
            case .success(let relaySelector):
                if let mullvadEndpoint = relaySelector.evaluate(with: tunnelConfiguration.relayConstraints) {
                    self.configureTunnel(
                        tunnelConfiguration: tunnelConfiguration,
                        mullvadEndpoint: mullvadEndpoint,
                        completionHandler: completionHandler)
                } else {
                    completionHandler(PacketTunnelProviderError.noRelaySatisfyingConstraint)
                }

            case .failure(let error):
                os_log(.error, "Failed to initialize the relay selector: %s",
                       error.localizedDescription)
                completionHandler(PacketTunnelProviderError.readRelayCache)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        os_log(.info, "Stopping the tunnel")

        networkMonitor?.cancel()
        networkMonitor = nil

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

    private func configureLogger() {
        wgSetLogger { level, msgC in
            guard let msgC = msgC else { return }
            let logType: OSLogType
            switch level {
            case 0:
                logType = .debug
            case 1:
                logType = .info
            case 2:
                logType = .error
            default:
                logType = .default
            }

            let swiftString = String(cString: msgC)

            os_log(.debug, "Wireguard: %{public}s", swiftString)
        }
    }

    private func configureTunnel(tunnelConfiguration: TunnelConfiguration,
                                 mullvadEndpoint: MullvadEndpoint,
                                 completionHandler: @escaping (Error?) -> Void)
    {
        let packetTunnelConfigGenerator = PacketTunnelSettingsGenerator(
            mullvadEndpoint: mullvadEndpoint,
            tunnelConfiguration: tunnelConfiguration)

        self.packetTunnelSettingsGenerator = packetTunnelConfigGenerator

        let networkSettings = packetTunnelConfigGenerator.networkSettings()

        setTunnelNetworkSettings(networkSettings) { (error) in
            if let error = error {
                os_log(.error, "Cannot set network settings: %{public}s", error.localizedDescription)

                completionHandler(PacketTunnelProviderError.setNetworkSettings)
            } else {
                let networkMonitor = NWPathMonitor()
                networkMonitor.pathUpdateHandler = { [weak self] in self?.didReceiveNetworkPathUpdate(path: $0) }
                networkMonitor.start(queue: self.networkMonitorQueue)
                self.networkMonitor = networkMonitor

                let fileDescriptor = self.getTunnelInterfaceDescriptor()
                if fileDescriptor < 0 {
                    os_log(.error, "Cannot find the file descriptor for socket.")
                    completionHandler(PacketTunnelProviderError.fileDescriptorNotFound)
                    return
                }

                self.tunnelInterfaceName = self.getInterfaceName(fileDescriptor)

                os_log(.info, "Tunnel interface is %{public}s", self.tunnelInterfaceName ?? "unknown")

                let handle = packetTunnelConfigGenerator.wireguardUapiConfiguration()
                    .withGoString { wgTurnOn($0, fileDescriptor) }

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

}

extension PacketTunnelProvider {

    private func didReceiveNetworkPathUpdate(path: Network.NWPath) {
        guard let handle = self.handle, let tunnelInterfaceName = self.tunnelInterfaceName else {
            return
        }

        os_log(.info,
               "Network change detected with %{public}s route and interface order %s",
               path.status.debugDescription,
               path.availableInterfaces.debugDescription)

        guard path.status == .satisfied else { return }

        if let packetTunnelSettingsGenerator = packetTunnelSettingsGenerator {
            _ = packetTunnelSettingsGenerator.wireguardEndpointUapiConfiguration()
                .withGoString { wgSetConfig(handle, $0) }
        }

        let interfaces = path.availableInterfaces.filter { $0.name != tunnelInterfaceName }.compactMap { $0.name }
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
    func withGoString<R>(_ call: (gostring_t) -> R) -> R {
        func helper(_ pointer: UnsafePointer<Int8>?, _ call: (gostring_t) -> R) -> R {
            return call(gostring_t(p: pointer, n: utf8.count))
        }
        return helper(self, call)
    }
}
