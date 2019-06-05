#pragma once

#include <string>
#include <memory>
#include <vector>
#include <stdexcept>
#include <winsock2.h>
#include <windows.h>
#include <ws2def.h>
#include <ws2ipdef.h>
#include <iphlpapi.h>
#include <netioapi.h>

namespace routemanager {

using Network = IP_ADDRESS_PREFIX;
using NodeAddress = SOCKADDR_INET;

class Node
{
public:

	Node(const std::wstring *deviceName, const NodeAddress *gateway)
	{
		if (nullptr == deviceName && nullptr == gateway)
		{
			throw std::runtime_error("Invalid 'Node' definition");
		}

		if (nullptr != deviceName)
		{
			m_deviceName = std::make_unique<std::wstring>(*deviceName);
		}

		if (nullptr != gateway)
		{
			m_gateway = std::make_unique<NodeAddress>(*gateway);
		}
	}

	Node(const Node &rhs)
	{
		if (rhs.m_deviceName)
		{
			m_deviceName = std::make_unique<std::wstring>(*rhs.m_deviceName);
		}

		if (rhs.m_gateway)
		{
			m_gateway = std::make_unique<NodeAddress>(*rhs.m_gateway);
		}
	}

	Node(Node &&rhs)
		: m_deviceName(std::move(rhs.m_deviceName))
		, m_gateway(std::move(rhs.m_gateway))
	{
	}

	bool hasDeviceName() const
	{
		return !!m_deviceName;
	}

	const std::wstring &deviceName() const
	{
		return *m_deviceName;
	}

	bool hasGateway() const
	{
		return !!m_gateway;
	}

	const NodeAddress &gateway() const
	{
		return *m_gateway;
	}

private:

	std::unique_ptr<std::wstring> m_deviceName;
	std::unique_ptr<NodeAddress> m_gateway;
};

class Route
{
public:

	Route(const Network &network, const Node *node)
		: m_network(network)
	{
		if (nullptr != node)
		{
			m_node = std::make_unique<Node>(*node);
		}
	}

	Route(const Route &rhs)
	{
		m_network = rhs.m_network;

		if (rhs.m_node)
		{
			m_node = std::make_unique<Node>(*rhs.m_node);
		}
	}

	Route(Route &&rhs)
		: m_network(std::move(rhs.m_network))
		, m_node(std::move(rhs.m_node))
	{
	}

	const Network &network() const
	{
		return m_network;
	}

	bool hasNode() const
	{
		return !!m_node;
	}

	const Node &node() const
	{
		return *m_node;
	}

private:

	Network m_network;
	std::unique_ptr<Node> m_node;
};

class RouteManager
{
public:

	RouteManager(const std::vector<Route> &routes);
	~RouteManager();

private:

	std::vector<Route> m_routes;
};

}
