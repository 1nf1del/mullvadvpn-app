use super::{Config, Error, Result, Tunnel};
use crate::tunnel::tun_provider::{Tun, TunProvider};
use cfg_if::cfg_if;

#[cfg(not(target_os = "windows"))]
use crate::tunnel::tun_provider::TunConfig;

#[cfg(target_os = "windows")]
use crate::tunnel::tun_provider::windows::WinTun;
use ipnetwork::IpNetwork;

#[cfg(target_os = "android")]
use talpid_types::BoxedError;

use std::{ffi::CString, fs, path::Path};

#[cfg(not(target_os = "windows"))]
use std::net::IpAddr;

#[cfg(not(target_os = "windows"))]
use std::os::unix::io::AsRawFd;

#[cfg(target_os = "windows")]
use std::ffi::CStr;

#[cfg(target_os = "windows")]
use std::os::windows::io::AsRawHandle;

pub struct WgGoTunnel {
    interface_name: String,
    handle: Option<i32>,
    // holding on to the tunnel device and the log file ensures that the associated file handles
    // live long enough and get closed when the tunnel is stopped
    _tunnel_device: Box<dyn Tun>,
    _log_file: fs::File,
}

impl WgGoTunnel {
    #[cfg(not(target_os = "windows"))]
    pub fn start_tunnel(
        config: &Config,
        log_path: Option<&Path>,
        tun_provider: &dyn TunProvider,
        routes: impl Iterator<Item = IpNetwork>,
    ) -> Result<Self> {
        #[cfg_attr(not(target_os = "android"), allow(unused_mut))]
        let mut tunnel_device = tun_provider
            .create_tun(Self::create_tunnel_config(config, routes))
            .map_err(Error::SetupTunnelDeviceError)?;

        let interface_name: String = tunnel_device.interface_name().to_string();
        let log_file = prepare_log_file(log_path)?;

        let wg_config_str = config.to_userspace_format();
        let iface_name =
            CString::new(interface_name.as_bytes()).map_err(Error::InterfaceNameError)?;

        let handle = unsafe {
            wgTurnOnWithFd(
                iface_name.as_ptr() as *const i8,
                config.mtu as i64,
                wg_config_str.as_ptr() as *const i8,
                tunnel_device.as_raw_fd(),
                log_file.as_raw_fd(),
                WG_GO_LOG_DEBUG,
            )
        };

        if handle < 0 {
            return Err(Error::StartWireguardError { status: handle });
        }

        #[cfg(target_os = "android")]
        Self::bypass_tunnel_sockets(&mut tunnel_device, handle).map_err(Error::BypassError)?;

        Ok(WgGoTunnel {
            interface_name,
            handle: Some(handle),
            _tunnel_device: tunnel_device,
            _log_file: log_file,
        })
    }

    #[cfg(target_os = "windows")]
    pub fn start_tunnel(
        config: &Config,
        log_path: Option<&Path>,
        _tun_provider: &dyn TunProvider,
        _routes: impl Iterator<Item = IpNetwork>,
    ) -> Result<Self> {
        let log_file = prepare_log_file(log_path)?;
        let wg_config_str = config.to_userspace_format();
        let iface_name = CString::new(String::from("wg-mullvad").as_bytes())
            .map_err(Error::InterfaceNameError)?;

        let mut real_iface_name_raw: *mut i8 = std::ptr::null_mut();

        let handle = unsafe {
            wgTurnOn(
                iface_name.as_ptr(),
                config.mtu as i64,
                wg_config_str.as_ptr(),
                log_file.as_raw_handle(),
                WG_GO_LOG_DEBUG,
                &mut real_iface_name_raw as *mut _,
            )
        };

        if handle < 0 {
            return Err(Error::StartWireguardError { status: handle });
        }

        if real_iface_name_raw.is_null() {
            return Err(Error::InterfaceNameIsNull);
        }
        let real_interface_name = unsafe { CStr::from_ptr(real_iface_name_raw).to_string_lossy() };

        Ok(WgGoTunnel {
            interface_name: real_interface_name.to_string(),
            handle: Some(handle),
            _tunnel_device: Box::new(WinTun {
                interface_name: real_interface_name.to_string(),
            }),
            _log_file: log_file,
        })
    }

    #[cfg(not(target_os = "windows"))]
    fn create_tunnel_config(config: &Config, routes: impl Iterator<Item = IpNetwork>) -> TunConfig {
        let mut dns_servers = vec![IpAddr::V4(config.ipv4_gateway)];
        dns_servers.extend(config.ipv6_gateway.map(IpAddr::V6));

        TunConfig {
            addresses: config.tunnel.addresses.clone(),
            dns_servers,
            routes: routes.collect(),
            mtu: config.mtu,
        }
    }

    #[cfg(target_os = "android")]
    fn bypass_tunnel_sockets(
        tunnel_device: &mut Box<dyn Tun>,
        handle: i32,
    ) -> std::result::Result<(), BoxedError> {
        let socket_v4 = unsafe { wgGetSocketV4(handle) };
        let socket_v6 = unsafe { wgGetSocketV6(handle) };

        tunnel_device.bypass(socket_v4)?;
        tunnel_device.bypass(socket_v6)?;

        Ok(())
    }

    fn stop_tunnel(&mut self) -> Result<()> {
        if let Some(handle) = self.handle.take() {
            let status = unsafe { wgTurnOff(handle) };
            if status < 0 {
                return Err(Error::StopWireguardError { status });
            }
        }
        Ok(())
    }
}

impl Drop for WgGoTunnel {
    fn drop(&mut self) {
        if let Err(e) = self.stop_tunnel() {
            log::error!("Failed to stop tunnel - {}", e);
        }
    }
}

cfg_if! {
    if #[cfg(not(target_os = "windows"))] {
        static NULL_DEVICE: &str = "/dev/null";
    } else {
        static NULL_DEVICE: &str = "NUL";
    }
}

fn prepare_log_file(log_path: Option<&Path>) -> Result<fs::File> {
    fs::File::create(log_path.unwrap_or(NULL_DEVICE.as_ref())).map_err(Error::PrepareLogFileError)
}

impl Tunnel for WgGoTunnel {
    fn get_interface_name(&self) -> &str {
        &self.interface_name
    }

    fn stop(mut self: Box<Self>) -> Result<()> {
        self.stop_tunnel()
    }
}

#[cfg(unix)]
pub type Fd = std::os::unix::io::RawFd;

#[cfg(windows)]
pub type Fd = std::os::windows::io::RawHandle;

type WgLogLevel = i32;
// wireguard-go supports log levels 0 through 3 with 3 being the most verbose
const WG_GO_LOG_DEBUG: WgLogLevel = 3;

extern "C" {
    // Creates a new wireguard tunnel, uses the specific interface name, MTU and file descriptors
    // for the tunnel device and logging.
    //
    // Positive return values are tunnel handles for this specific wireguard tunnel instance.
    // Negative return values signify errors. All error codes are opaque.
    #[cfg(not(target_os = "windows"))]
    fn wgTurnOnWithFd(
        iface_name: *const i8,
        mtu: i64,
        settings: *const i8,
        fd: Fd,
        log_fd: Fd,
        logLevel: WgLogLevel,
    ) -> i32;

    // Windows
    #[cfg(target_os = "windows")]
    fn wgTurnOn(
        iface_name: *const i8,
        mtu: i64,
        settings: *const i8,
        log_fd: Fd,
        logLevel: WgLogLevel,
        real_interface_name: *mut *mut i8,
    ) -> i32;

    // Pass a handle that was created by wgTurnOnWithFd to stop a wireguard tunnel.
    fn wgTurnOff(handle: i32) -> i32;

    // Returns the file descriptor of the tunnel IPv4 socket.
    #[cfg(target_os = "android")]
    fn wgGetSocketV4(handle: i32) -> Fd;

    // Returns the file descriptor of the tunnel IPv6 socket.
    #[cfg(target_os = "android")]
    fn wgGetSocketV6(handle: i32) -> Fd;
}
