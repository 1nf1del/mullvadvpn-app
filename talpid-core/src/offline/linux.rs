use crate::tunnel_state_machine::TunnelCommand;
use futures::{future::Either, sync::mpsc::UnboundedSender, Future, Stream};
use iproute2::{Address, Connection, ConnectionHandle, Link, NetlinkIpError};
use log::{error, warn};
use netlink_socket::{Protocol, SocketAddr, TokioSocket};
use rtnetlink::{LinkLayerType, NetlinkCodec, NetlinkFramed, NetlinkMessage};
use std::{collections::BTreeSet, io, thread};
use talpid_types::ErrorExt;


pub type Result<T> = std::result::Result<T, Error>;

#[derive(err_derive::Error, Debug)]
pub enum Error {
    #[error(display = "Failed to get list of IP links")]
    GetLinksError(#[error(cause)] failure::Compat<iproute2::NetlinkIpError>),

    #[error(display = "Failed to connect to netlink socket")]
    NetlinkConnectionError(#[error(cause)] io::Error),

    #[error(display = "Failed to start listening on netlink socket")]
    NetlinkBindError(#[error(cause)] io::Error),

    #[error(display = "Error while communicating on the netlink socket")]
    NetlinkError(#[error(cause)] io::Error),

    #[error(display = "Error while processing netlink messages")]
    MonitorNetlinkError(#[error(cause)] failure::Compat<rtnetlink::Error>),

    #[error(display = "Netlink connection has unexpectedly disconnected")]
    NetlinkDisconnected,
}

const RTMGRP_NOTIFY: u32 = 1;
const RTMGRP_LINK: u32 = 2;
const RTMGRP_IPV4_IFADDR: u32 = 0x10;
const RTMGRP_IPV6_IFADDR: u32 = 0x100;

pub struct MonitorHandle;

pub fn spawn_monitor(sender: UnboundedSender<TunnelCommand>) -> Result<MonitorHandle> {
    let mut socket = TokioSocket::new(Protocol::Route).map_err(Error::NetlinkConnectionError)?;
    socket
        .bind(&SocketAddr::new(
            0,
            RTMGRP_NOTIFY | RTMGRP_LINK | RTMGRP_IPV4_IFADDR | RTMGRP_IPV6_IFADDR,
        ))
        .map_err(Error::NetlinkBindError)?;

    let channel = NetlinkFramed::new(socket, NetlinkCodec::<NetlinkMessage>::new());
    let link_monitor = LinkMonitor::new(sender);

    thread::spawn(|| {
        if let Err(error) = monitor_event_loop(channel, link_monitor) {
            error!(
                "{}",
                error.display_chain_with_msg("Error running link monitor event loop")
            );
        }
    });

    Ok(MonitorHandle)
}

pub fn is_offline() -> bool {
    check_if_offline().unwrap_or_else(|error| {
        warn!(
            "{}",
            error.display_chain_with_msg("Failed to check for internet connection")
        );
        false
    })
}

/// Checks if there are no running links or that none of the running links have IP addresses
/// assigned to them.
fn check_if_offline() -> Result<bool> {
    let mut connection = NetlinkConnection::new()?;
    let interfaces = connection.running_interfaces()?;

    if interfaces.is_empty() {
        Ok(true)
    } else {
        // Check if the current IP addresses are not assigned to any one of the running interfaces
        Ok(connection
            .addresses()?
            .into_iter()
            .all(|address| !interfaces.contains(&address.index())))
    }
}

struct NetlinkConnection {
    connection: Option<Connection>,
    connection_handle: ConnectionHandle,
}

impl NetlinkConnection {
    /// Open a connection on the netlink socket.
    pub fn new() -> Result<Self> {
        let (connection, connection_handle) =
            iproute2::new_connection().map_err(Error::NetlinkConnectionError)?;

        Ok(NetlinkConnection {
            connection: Some(connection),
            connection_handle,
        })
    }

    /// List all IP addresses assigned to all interfaces.
    pub fn addresses(&mut self) -> Result<Vec<Address>> {
        self.execute_request(self.connection_handle.address().get().execute())
    }

    /// List all links registered on the system.
    fn links(&mut self) -> Result<Vec<Link>> {
        self.execute_request(self.connection_handle.link().get().execute())
    }

    /// List all unique interface indices that have a running link.
    pub fn running_interfaces(&mut self) -> Result<BTreeSet<u32>> {
        let links = self.links()?;

        Ok(links
            .into_iter()
            .filter(link_provides_connectivity)
            .map(|link| link.index())
            .collect())
    }

    /// Helper function to execute an asynchronous request synchronously.
    fn execute_request<R>(&mut self, request: R) -> Result<R::Item>
    where
        R: Future<Error = NetlinkIpError>,
    {
        let connection = self.connection.take().ok_or(Error::NetlinkDisconnected)?;

        let (result, connection) = match connection.select2(request).wait() {
            Ok(Either::A(_)) => return Err(Error::NetlinkDisconnected),
            Err(Either::A((error, _))) => return Err(Error::NetlinkError(error)),
            Ok(Either::B((links, connection))) => (Ok(links), connection),
            Err(Either::B((error, connection))) => (
                Err(Error::GetLinksError(failure::Fail::compat(error))),
                connection,
            ),
        };

        self.connection = Some(connection);
        result
    }
}

fn link_provides_connectivity(link: &Link) -> bool {
    // Some tunnels have the link layer type set to None
    link.link_layer_type() != LinkLayerType::Loopback
        && link.link_layer_type() != LinkLayerType::None
        && link.flags().is_running()
}

fn monitor_event_loop(
    channel: NetlinkFramed<NetlinkCodec<NetlinkMessage>>,
    mut link_monitor: LinkMonitor,
) -> Result<()> {
    channel
        .for_each(|(_message, _address)| {
            link_monitor.update();
            Ok(())
        })
        .wait()
        .map_err(|error| Error::MonitorNetlinkError(failure::Fail::compat(error)))?;

    Ok(())
}

struct LinkMonitor {
    is_offline: bool,
    sender: UnboundedSender<TunnelCommand>,
}

impl LinkMonitor {
    pub fn new(sender: UnboundedSender<TunnelCommand>) -> Self {
        let is_offline = is_offline();

        LinkMonitor { is_offline, sender }
    }

    pub fn update(&mut self) {
        self.set_is_offline(is_offline());
    }

    fn set_is_offline(&mut self, is_offline: bool) {
        if self.is_offline != is_offline {
            self.is_offline = is_offline;
            let _ = self
                .sender
                .unbounded_send(TunnelCommand::IsOffline(is_offline));
        }
    }
}
