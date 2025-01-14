use crate::{location, new_rpc_client, Command, Error, Result};
use clap::{value_t, values_t};
use std::{
    io::{self, BufRead},
    net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr},
    str::FromStr,
};

use mullvad_types::{
    relay_constraints::{
        Constraint, OpenVpnConstraints, RelayConstraintsUpdate, RelaySettingsUpdate,
        TunnelProtocol, WireguardConstraints,
    },
    ConnectionConfig, CustomTunnelEndpoint,
};
use talpid_types::net::{all_of_the_internet, openvpn, wireguard, Endpoint, TransportProtocol};

pub struct Relay;

impl Command for Relay {
    fn name(&self) -> &'static str {
        "relay"
    }

    fn clap_subcommand(&self) -> clap::App<'static, 'static> {
        clap::SubCommand::with_name(self.name())
            .about("Manage relay and tunnel constraints")
            .setting(clap::AppSettings::SubcommandRequiredElseHelp)
            .subcommand(
                clap::SubCommand::with_name("set")
                    .about(
                        "Set relay server selection parameters. Such as location and port/protocol",
                    )
                    .setting(clap::AppSettings::SubcommandRequiredElseHelp)
                    .subcommand(
                        clap::SubCommand::with_name("custom")
                            .about("Set a custom VPN relay")
                            .subcommand(clap::SubCommand::with_name("wireguard")
                                .arg(
                                    clap::Arg::with_name("host")
                                        .help("Hostname or IP")
                                        .required(true)
                                        .index(1),
                                )
                                .arg(
                                    clap::Arg::with_name("port")
                                        .help("Remote network port")
                                        .required(true)
                                        .index(2),
                                )
                                .arg(
                                    clap::Arg::with_name("peer-key")
                                        .help("Base64 encoded peer public key")
                                        .index(3)
                                        .required(false),
                                )
                                .arg(
                                    clap::Arg::with_name("v4-gateway")
                                        .help("IPv4 gateway address")
                                        .long("v4-gateway")
                                        .index(4)
                                        .required(false),
                                ).arg(
                                    clap::Arg::with_name("v6-gateway")
                                        .help("IPv6 gateway address")
                                        .long("v6-gateway")
                                        .takes_value(true)
                                        .required(false),
                                )
                                .arg(
                                    clap::Arg::with_name("addr")
                                        .help("Local address of wireguard tunnel")
                                        .long("addr")
                                        .takes_value(true)
                                        .multiple(true)
                                        .required(false),
                                ),
                            )
                            .subcommand(clap::SubCommand::with_name("openvpn")
                                .arg(
                                    clap::Arg::with_name("host")
                                        .help("Hostname or IP")
                                        .required(true)
                                        .index(1),
                                )
                                .arg(
                                    clap::Arg::with_name("port")
                                        .help("Remote network port")
                                        .required(true)
                                        .index(2),
                                )
                                .arg(
                                    clap::Arg::with_name("protocol")
                                        .help("Transport protocol. For Wireguard this is ignored.")
                                        .index(3)
                                        .default_value("udp")
                                        .possible_values(&["udp", "tcp"]),
                                )
                                .arg(
                                    clap::Arg::with_name("username")
                                        .help("Username to be used with the OpenVpn relay")
                                        .index(4),
                                )
                                .arg(
                                    clap::Arg::with_name("password")
                                        .help("Password to be used with the OpenVpn relay")
                                        .index(5),
                                )
                            )
                    )
                    .subcommand(
                        location::get_subcommand()
                            .about("Set country or city to select relays from. Use the 'list' \
                                   command to show available alternatives.")
                    )
                    .subcommand(
                        clap::SubCommand::with_name("tunnel")
                            .about("Set tunnel constraints")
                            .arg(
                                clap::Arg::with_name("vpn protocol")
                                    .required(true)
                                    .index(1)
                                    .possible_values(&["wireguard", "openvpn"]),
                            )
                            .arg(clap::Arg::with_name("port").required(true).index(2))
                            .arg(
                                clap::Arg::with_name("transport protocol")
                                    .long("protocol")
                                    .required(false)
                                    .default_value("any")
                                    .possible_values(&["any", "udp", "tcp"]),
                            ),

                    ),
            )
            .subcommand(clap::SubCommand::with_name("get"))
            .subcommand(
                clap::SubCommand::with_name("list").about("List available countries and cities"),
            )
            .subcommand(
                clap::SubCommand::with_name("update")
                    .about("Update the list of available countries and cities"),
            )
    }

    fn run(&self, matches: &clap::ArgMatches<'_>) -> Result<()> {
        if let Some(set_matches) = matches.subcommand_matches("set") {
            self.set(set_matches)
        } else if matches.subcommand_matches("get").is_some() {
            self.get()
        } else if matches.subcommand_matches("list").is_some() {
            self.list()
        } else if matches.subcommand_matches("update").is_some() {
            self.update()
        } else {
            unreachable!("No relay command given");
        }
    }
}

impl Relay {
    fn update_constraints(&self, update: RelaySettingsUpdate) -> Result<()> {
        let mut rpc = new_rpc_client()?;
        rpc.update_relay_settings(update)?;
        println!("Relay constraints updated");
        Ok(())
    }

    fn set(&self, matches: &clap::ArgMatches<'_>) -> Result<()> {
        if let Some(custom_matches) = matches.subcommand_matches("custom") {
            self.set_custom(custom_matches)
        } else if let Some(location_matches) = matches.subcommand_matches("location") {
            self.set_location(location_matches)
        } else if let Some(tunnel_matches) = matches.subcommand_matches("tunnel") {
            self.set_tunnel(tunnel_matches)
        } else {
            unreachable!("No set relay command given");
        }
    }

    fn set_custom(&self, matches: &clap::ArgMatches<'_>) -> Result<()> {
        let custom_endpoint = match matches.subcommand() {
            ("openvpn", Some(openvpn_matches)) => Self::read_custom_openvpn_relay(openvpn_matches),
            ("wireguard", Some(wg_matches)) => Self::read_custom_wireguard_relay(wg_matches),
            (_unknown_tunnel, _) => unreachable!("No set relay command given"),
        };
        self.update_constraints(RelaySettingsUpdate::CustomTunnelEndpoint(custom_endpoint))
    }

    fn read_custom_openvpn_relay(matches: &clap::ArgMatches<'_>) -> CustomTunnelEndpoint {
        let host = value_t!(matches.value_of("host"), String).unwrap_or_else(|e| e.exit());
        let port = value_t!(matches.value_of("port"), u16).unwrap_or_else(|e| e.exit());
        let username = value_t!(matches.value_of("username"), String).unwrap_or_else(|e| e.exit());
        let password = value_t!(matches.value_of("password"), String).unwrap_or_else(|e| e.exit());
        let protocol =
            value_t!(matches.value_of("protocol"), TransportProtocol).unwrap_or_else(|e| e.exit());
        CustomTunnelEndpoint::new(
            host,
            ConnectionConfig::OpenVpn(openvpn::ConnectionConfig {
                endpoint: Endpoint::new(Ipv4Addr::UNSPECIFIED, port, protocol),
                username,
                password,
            }),
        )
    }

    fn read_custom_wireguard_relay(matches: &clap::ArgMatches<'_>) -> CustomTunnelEndpoint {
        let host = value_t!(matches.value_of("host"), String).unwrap_or_else(|e| e.exit());
        let port = value_t!(matches.value_of("port"), u16).unwrap_or_else(|e| e.exit());
        let addresses = values_t!(matches.values_of("addr"), IpAddr).unwrap_or_else(|e| e.exit());
        let peer_key_str =
            value_t!(matches.value_of("peer-key"), String).unwrap_or_else(|e| e.exit());
        let ipv4_gateway =
            value_t!(matches.value_of("v4-gateway"), Ipv4Addr).unwrap_or_else(|e| e.exit());
        let ipv6_gateway = match value_t!(matches.value_of("v6-gateway"), Ipv6Addr) {
            Ok(gateway) => Some(gateway),
            Err(e) => match e.kind {
                clap::ErrorKind::ArgumentNotFound => None,
                _ => e.exit(),
            },
        };
        let mut private_key_str = String::new();
        println!("Reading private key from standard input");
        let _ = io::stdin().lock().read_line(&mut private_key_str);
        if private_key_str.trim().is_empty() {
            eprintln!("Expected to read private key from standard input");
        }
        let private_key = Self::validate_wireguard_key(&private_key_str).into();
        let peer_public_key = Self::validate_wireguard_key(&peer_key_str).into();


        CustomTunnelEndpoint::new(
            host,
            ConnectionConfig::Wireguard(wireguard::ConnectionConfig {
                tunnel: wireguard::TunnelConfig {
                    private_key,
                    addresses,
                },
                peer: wireguard::PeerConfig {
                    public_key: peer_public_key,
                    allowed_ips: all_of_the_internet(),
                    endpoint: SocketAddr::new(Ipv4Addr::UNSPECIFIED.into(), port),
                },
                ipv4_gateway,
                ipv6_gateway,
            }),
        )
    }

    fn validate_wireguard_key(key_str: &str) -> [u8; 32] {
        let key_bytes = base64::decode(key_str.trim()).unwrap_or_else(|e| {
            eprintln!("Failed to decode wireguard key: {}", e);
            ::std::process::exit(1);
        });

        let mut key = [0u8; 32];
        if key_bytes.len() != 32 {
            eprintln!(
                "Expected key length to be 32 bytes, got {}",
                key_bytes.len()
            );
            ::std::process::exit(1);
        }

        key.copy_from_slice(&key_bytes);
        key
    }

    fn set_location(&self, matches: &clap::ArgMatches<'_>) -> Result<()> {
        let location_constraint = location::get_constraint(matches);

        self.update_constraints(RelaySettingsUpdate::Normal(RelayConstraintsUpdate {
            location: Some(location_constraint),
            ..Default::default()
        }))
    }

    fn set_tunnel(&self, matches: &clap::ArgMatches<'_>) -> Result<()> {
        let vpn_protocol = matches.value_of("vpn protocol").unwrap();
        let port = parse_port_constraint(matches.value_of("port").unwrap())?;
        let protocol = parse_protocol_constraint(matches.value_of("transport protocol").unwrap());

        match vpn_protocol {
            "wireguard" => {
                if let Constraint::Only(TransportProtocol::Tcp) = protocol {
                    return Err(Error::InvalidCommand("WireGuard does not support TCP"));
                }
                self.update_constraints(RelaySettingsUpdate::Normal(RelayConstraintsUpdate {
                    location: None,
                    tunnel_protocol: Some(Constraint::Only(TunnelProtocol::Wireguard)),
                    wireguard_constraints: Some(WireguardConstraints { port }),
                    ..Default::default()
                }))
            }
            "openvpn" => {
                self.update_constraints(RelaySettingsUpdate::Normal(RelayConstraintsUpdate {
                    location: None,
                    tunnel_protocol: Some(Constraint::Any),
                    openvpn_constraints: Some(OpenVpnConstraints { port, protocol }),
                    ..Default::default()
                }))
            }
            _ => unreachable!(),
        }
    }

    fn get(&self) -> Result<()> {
        let mut rpc = new_rpc_client()?;
        let constraints = rpc.get_settings()?.get_relay_settings();
        println!("Current constraints: {}", constraints);

        Ok(())
    }

    fn list(&self) -> Result<()> {
        let mut rpc = new_rpc_client()?;
        let mut locations = rpc.get_relay_locations()?;
        locations.countries.sort_by(|c1, c2| c1.name.cmp(&c2.name));
        for mut country in locations.countries {
            country.cities.sort_by(|c1, c2| c1.name.cmp(&c2.name));
            println!("{} ({})", country.name, country.code);
            for city in &country.cities {
                println!(
                    "\t{} ({}) @ {:.5}°N, {:.5}°W",
                    city.name, city.code, city.latitude, city.longitude
                );
            }
            println!();
        }
        Ok(())
    }

    fn update(&self) -> Result<()> {
        new_rpc_client()?.update_relay_locations()?;
        println!("Updating relay list in the background...");
        Ok(())
    }
}


fn parse_port_constraint(raw_port: &str) -> Result<Constraint<u16>> {
    match raw_port.to_lowercase().as_str() {
        "any" => Ok(Constraint::Any),
        port => Ok(Constraint::Only(u16::from_str(port).map_err(|_| {
            Error::InvalidCommand("Invalid port. Must be \"any\" or [0-65535].")
        })?)),
    }
}

/// Parses a protocol constraint string. Can be infallible because the possible values are limited
/// with clap.
fn parse_protocol_constraint(raw_protocol: &str) -> Constraint<TransportProtocol> {
    match raw_protocol {
        "any" => Constraint::Any,
        "udp" => Constraint::Only(TransportProtocol::Udp),
        "tcp" => Constraint::Only(TransportProtocol::Tcp),
        _ => unreachable!(),
    }
}
