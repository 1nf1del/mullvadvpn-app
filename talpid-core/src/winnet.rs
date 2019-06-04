use self::api::*;
pub use self::api::{
    ErrorSink, WinNet_ActivateConnectivityMonitor, WinNet_DeactivateConnectivityMonitor,
};
use crate::routing::Node;
use ipnetwork::IpNetwork;
use libc::{c_char, c_void, wchar_t};
use std::{ffi::OsString, net::IpAddr, ptr};
use widestring::WideCString;

/// Errors that this module may produce.
#[derive(err_derive::Error, Debug)]
pub enum Error {
    /// Failed to set the metrics for a network interface.
    #[error(display = "Failed to set the metrics for a network interface")]
    MetricApplication,

    /// Supplied interface alias is invalid.
    #[error(display = "Supplied interface alias is invalid")]
    InvalidInterfaceAlias(#[error(cause)] widestring::NulError<u16>),

    /// Failed to read IPv6 status on the TAP network interface.
    #[error(display = "Failed to read IPv6 status on the TAP network interface")]
    GetIpv6Status,

    /// Failed to determine alias of TAP adapter.
    #[error(display = "Failed to determine alias of TAP adapter")]
    GetTapAlias,

    /// Can't establish whether host is connected to a non-virtual network
    #[error(display = "Network connectivity undecideable")]
    ConnectivityUnkown,
}

/// Error callback used with `winnet.dll`.
pub extern "system" fn error_sink(msg: *const c_char, _ctx: *mut c_void) {
    use std::ffi::CStr;
    if msg.is_null() {
        log::error!("Log message from FFI boundary is NULL");
    } else {
        log::error!("{}", unsafe { CStr::from_ptr(msg).to_string_lossy() });
    }
}

/// Returns true if metrics were changed, false otherwise
pub fn ensure_top_metric_for_interface(interface_alias: &str) -> Result<bool, Error> {
    let interface_alias_ws =
        WideCString::from_str(interface_alias).map_err(Error::InvalidInterfaceAlias)?;

    let metric_result = unsafe {
        WinNet_EnsureTopMetric(
            interface_alias_ws.as_ptr(),
            Some(error_sink),
            ptr::null_mut(),
        )
    };

    match metric_result {
        // Metrics didn't change
        0 => Ok(false),
        // Metrics changed
        1 => Ok(true),
        // Failure
        2 => Err(Error::MetricApplication),
        // Unexpected value
        i => {
            log::error!("Unexpected return code from WinNet_EnsureTopMetric: {}", i);
            Err(Error::MetricApplication)
        }
    }
}

/// Checks if IPv6 is enabled for the TAP interface
pub fn get_tap_interface_ipv6_status() -> Result<bool, Error> {
    let tap_ipv6_status =
        unsafe { WinNet_GetTapInterfaceIpv6Status(Some(error_sink), ptr::null_mut()) };

    match tap_ipv6_status {
        // Enabled
        0 => Ok(true),
        // Disabled
        1 => Ok(false),
        // Failure
        2 => Err(Error::GetIpv6Status),
        // Unexpected value
        i => {
            log::error!(
                "Unexpected return code from WinNet_GetTapInterfaceIpv6Status: {}",
                i
            );
            Err(Error::GetIpv6Status)
        }
    }
}

/// Dynamically determines the alias of the TAP adapter.
pub fn get_tap_interface_alias() -> Result<OsString, Error> {
    let mut alias_ptr: *mut wchar_t = ptr::null_mut();
    let status = unsafe {
        WinNet_GetTapInterfaceAlias(&mut alias_ptr as *mut _, Some(error_sink), ptr::null_mut())
    };

    if !status {
        return Err(Error::GetTapAlias);
    }

    let alias = unsafe { WideCString::from_ptr_str(alias_ptr) };
    unsafe { WinNet_ReleaseString(alias_ptr) };

    Ok(alias.to_os_string())
}
/// Returns true if current host is not connected to any network
pub fn is_offline() -> Result<bool, Error> {
    match unsafe { WinNet_CheckConnectivity(Some(error_sink), ptr::null_mut()) } {
        // Not connected
        0 => Ok(true),
        // Connected
        1 => Ok(false),
        // 2 means that connectivity can't be determined, but any other return value is unexpected
        // and as such, is considered to be an error.
        _ => Err(Error::ConnectivityUnkown),
    }
}

#[repr(packed)]
struct WinNetIpType(u8);

const WINNET_IPV4: u8 = 0;
const WINNET_IPV6: u8 = 1;

impl WinNetIpType {
    pub fn v4() -> Self {
        WinNetIpType(WINNET_IPV4)
    }

    pub fn v6() -> Self {
        WinNetIpType(WINNET_IPV6)
    }
}


#[repr(packed)]
pub struct WinNetIpNetwork {
    ip_type: WinNetIpType,
    ip_bytes: [u8; 16],
    prefix: u8,
}

impl From<IpNetwork> for WinNetIpNetwork {
    fn from(network: IpNetwork) -> WinNetIpNetwork {
        let WinNetIp{ip_type, ip_bytes} = WinNetIp::from(network.ip());
        let prefix = network.prefix();
        WinNetIpNetwork { ip_type, ip_bytes, prefix }
    }
}

#[repr(packed)]
pub struct WinNetIp {
    ip_type: WinNetIpType,
    ip_bytes: [u8; 16],
}

impl From<IpAddr> for WinNetIp {
    fn from(addr: IpAddr) -> WinNetIp {
        let mut bytes = [0u8; 16];
        match addr {
            IpAddr::V4(v4_addr) => {
                bytes[..4].copy_from_slice(&v4_addr.octets());
                WinNetIp {
                    ip_type: WinNetIpType::v4(),
                    ip_bytes: bytes,
                }
            }
            IpAddr::V6(v6_addr) => {
                bytes.copy_from_slice(&v6_addr.octets());

                WinNetIp {
                    ip_type: WinNetIpType::v6(),
                    ip_bytes: bytes,
                }
            }
        }
    }
}

#[repr(packed)]
pub struct WinNetNode {
    gateway: *mut WinNetIp,
    device_name: *mut u16,
}

impl WinNetNode {
    fn new(name: &str, ip: WinNetIp) -> Self {
        let device_name = WideCString::from_str(name)
            .expect("Failed to convert UTF-8 string to null terminated UCS string")
            .into_raw();
        let gateway = Box::into_raw(Box::new(ip));
        Self {
            gateway,
            device_name,
        }
    }

    fn from_gateway(ip: WinNetIp) -> Self {
        let gateway = Box::into_raw(Box::new(ip));
        Self {
            gateway,
            device_name: ptr::null_mut(),
        }
    }


    fn from_device(name: &str) -> Self {
        let device_name = WideCString::from_str(name)
            .expect("Failed to convert UTF-8 string to null terminated UCS string")
            .into_raw();
        Self {
            gateway: ptr::null_mut(),
            device_name,
        }
    }
}

impl From<&Node> for WinNetNode {
    fn from(node: &Node) -> Self {
        match (node.get_address(), node.get_device()) {
            (Some(gateway), None) => WinNetNode::from_gateway(gateway.into()),
            (None, Some(device)) => WinNetNode::from_device(device),
            (Some(gateway), Some(device)) => WinNetNode::new(device, gateway.into()),
            _ => unreachable!(),
        }
    }
}

impl Drop for WinNetNode {
    fn drop(&mut self) {
        if !self.gateway.is_null() {
            unsafe {
                let _ = Box::from_raw(self.gateway);
            }
        }
        if !self.device_name.is_null() {
            unsafe {
                let _ = WideCString::from_ptr_str(self.device_name);
            }
        }
    }
}


#[repr(packed)]
pub struct WinNetRoute {
    gateway: WinNetIpNetwork,
    node: *mut WinNetNode,
}

impl WinNetRoute {
    pub fn through_default_node(gateway: WinNetIpNetwork) -> Self {
        Self {
            gateway,
            node: ptr::null_mut(),
        }
    }

    pub fn new(node: WinNetNode, gateway: WinNetIpNetwork) -> Self {
        let node = Box::into_raw(Box::new(node));
        WinNetRoute { gateway, node }
    }
}

impl Drop for WinNetRoute {
    fn drop(&mut self) {
        if !self.node.is_null() {
            unsafe {
                let _ = Box::from_raw(self.node);
            }
            self.node = ptr::null_mut();
        }
    }
}

pub fn actiavte_routing_manager(routes: &[WinNetRoute]) -> bool {
    let ptr = routes.as_ptr();
    let length: u32 = routes.len() as u32;
    unsafe { WinNet_ActivateRouteManager(ptr, length, Some(error_sink), ptr::null_mut()) }
}

pub fn deactivate_routing_manager() -> bool {
    unsafe { WinNet_DeactivateRouteManager() }
}

#[allow(non_snake_case)]
mod api {
    use libc::{c_char, c_void, wchar_t};

    /// Error callback type for use with `winnet.dll`.
    pub type ErrorSink = extern "system" fn(msg: *const c_char, ctx: *mut c_void);

    pub type ConnectivityCallback = unsafe extern "system" fn(is_connected: bool, ctx: *mut c_void);

    extern "system" {
        #[link_name = "WinNet_ActivateRouteManager"]
        pub fn WinNet_ActivateRouteManager(
            routes: *const super::WinNetRoute,
            num_routes: u32,
            sink: Option<ErrorSink>,
            sink_context: *mut c_void,
        ) -> bool;

        #[link_name = "WinNet_DeactivateRouteManager"]
        pub fn WinNet_DeactivateRouteManager() -> bool;

        #[link_name = "WinNet_EnsureTopMetric"]
        pub fn WinNet_EnsureTopMetric(
            tunnel_interface_alias: *const wchar_t,
            sink: Option<ErrorSink>,
            sink_context: *mut c_void,
        ) -> u32;

        #[link_name = "WinNet_GetTapInterfaceIpv6Status"]
        pub fn WinNet_GetTapInterfaceIpv6Status(
            sink: Option<ErrorSink>,
            sink_context: *mut c_void,
        ) -> u32;

        #[link_name = "WinNet_GetTapInterfaceAlias"]
        pub fn WinNet_GetTapInterfaceAlias(
            tunnel_interface_alias: *mut *mut wchar_t,
            sink: Option<ErrorSink>,
            sink_context: *mut c_void,
        ) -> bool;

        #[link_name = "WinNet_ReleaseString"]
        pub fn WinNet_ReleaseString(string: *mut wchar_t) -> u32;

        #[link_name = "WinNet_ActivateConnectivityMonitor"]
        pub fn WinNet_ActivateConnectivityMonitor(
            callback: Option<ConnectivityCallback>,
            callbackContext: *mut libc::c_void,
            currentConnectivity: *mut bool,
            sink: Option<ErrorSink>,
            sink_context: *mut c_void,
        ) -> bool;

        #[link_name = "WinNet_DeactivateConnectivityMonitor"]
        pub fn WinNet_DeactivateConnectivityMonitor() -> bool;

        #[link_name = "WinNet_CheckConnectivity"]
        pub fn WinNet_CheckConnectivity(sink: Option<ErrorSink>, sink_context: *mut c_void) -> u32;
    }
}
