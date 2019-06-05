#include "stdafx.h"
#include "winnet.h"
#include "NetworkInterfaces.h"
#include "interfaceutils.h"
#include "libcommon/error.h"
#include "libcommon/network.h"
#include "netmonitor.h"
#include "routemanager.h"
#include <cstdint>
#include <stdexcept>

using namespace routemanager;

namespace
{

NetMonitor *g_NetMonitor = nullptr;
RouteManager *g_RouteManager = nullptr;

Network ConvertNetwork(const WINNET_IPNETWORK &in)
{
	//
	// Convert WINNET_IPNETWORK into Network aka IP_ADDRESS_PREFIX
	//

	Network out{ 0 };

	out.PrefixLength = in.prefix;

	switch (in.type)
	{
		case WINNET_IP_TYPE::IPV4:
		{
			out.Prefix.si_family = AF_INET;
			out.Prefix.Ipv4.sin_family = AF_INET;
			out.Prefix.Ipv4.sin_addr.s_addr = common::network::LiteralAddressToNetwork(in.bytes);

			break;
		}
		case WINNET_IP_TYPE::IPV6:
		{
			out.Prefix.si_family = AF_INET6;
			out.Prefix.Ipv6.sin6_family = AF_INET6;
			memcpy(out.Prefix.Ipv6.sin6_addr.u.Byte, in.bytes, 16);

			break;
		}
		default:
		{
			throw std::logic_error("Missing case handler in switch clause");
		}
	}

	return out;
}

std::unique_ptr<Node> ConvertNode(const WINNET_NODE *in)
{
	std::unique_ptr<Node> out;

	if (nullptr == in)
	{
		return out;
	}

	if (nullptr == in->gateway && nullptr == in->deviceName)
	{
		throw std::runtime_error("Invalid 'WINNET_NODE' definition");
	}

	//
	// Convert WINNET_NODE into Node
	//

	NodeAddress gatewayStorage{ 0 };
	const NodeAddress *gatewayPointer = nullptr;

	if (nullptr != in->gateway)
	{
		gatewayPointer = &gatewayStorage;

		switch (in->gateway->type)
		{
			case WINNET_IP_TYPE::IPV4:
			{
				gatewayStorage.si_family = AF_INET;
				gatewayStorage.Ipv4.sin_family = AF_INET;
				gatewayStorage.Ipv4.sin_addr.s_addr = common::network::LiteralAddressToNetwork(in->gateway->bytes);

				break;
			}
			case WINNET_IP_TYPE::IPV6:
			{
				gatewayStorage.si_family = AF_INET6;
				gatewayStorage.Ipv6.sin6_family = AF_INET6;
				memcpy(&gatewayStorage.Ipv6.sin6_addr.u.Byte, in->gateway->bytes, 16);

				break;
			}
			default:
			{
				throw std::logic_error("Missing case handler in switch clause");
			}
		}
	}

	std::wstring deviceNameStorage;
	const std::wstring *deviceNamePointer = nullptr;

	if (nullptr != in->deviceName)
	{
		deviceNamePointer = &deviceNameStorage;
		deviceNameStorage = in->deviceName;
	}

	out = std::make_unique<Node>(deviceNamePointer, gatewayPointer);

	return out;
}

std::vector<Route> ConvertRoutes(const WINNET_ROUTE *routes, uint32_t numRoutes)
{
	std::vector<Route> out;

	out.reserve(numRoutes);

	for (size_t i = 0; i < numRoutes; ++i)
	{
		out.emplace_back(Route
		{
			ConvertNetwork(routes[i].network),
			ConvertNode(routes[i].node).get()
		});
	}

	return out;
}

} //anonymous namespace

extern "C"
WINNET_LINKAGE
WINNET_ETM_STATUS
WINNET_API
WinNet_EnsureTopMetric(
	const wchar_t *deviceAlias,
	WinNetErrorSink errorSink,
	void *errorSinkContext
)
{
	try
	{
		NetworkInterfaces interfaces;
		bool metrics_set = interfaces.SetTopMetricForInterfacesByAlias(deviceAlias);
		return metrics_set ? WINNET_ETM_STATUS::METRIC_SET : WINNET_ETM_STATUS::METRIC_NO_CHANGE;
	}
	catch (std::exception &err)
	{
		if (nullptr != errorSink)
		{
			errorSink(err.what(), errorSinkContext);
		}

		return WINNET_ETM_STATUS::FAILURE;
	}
	catch (...)
	{
		return WINNET_ETM_STATUS::FAILURE;
	}
};

extern "C"
WINNET_LINKAGE
WINNET_GTII_STATUS
WINNET_API
WinNet_GetTapInterfaceIpv6Status(
	WinNetErrorSink errorSink,
	void *errorSinkContext
)
{
	try
	{
		MIB_IPINTERFACE_ROW iface = { 0 };

		iface.InterfaceLuid = NetworkInterfaces::GetInterfaceLuid(InterfaceUtils::GetTapInterfaceAlias());
		iface.Family = AF_INET6;

		const auto status = GetIpInterfaceEntry(&iface);

		if (NO_ERROR == status)
		{
			return WINNET_GTII_STATUS::ENABLED;
		}

		if (ERROR_NOT_FOUND == status)
		{
			return WINNET_GTII_STATUS::DISABLED;
		}

		common::error::Throw("Resolve TAP IPv6 interface", status);
	}
	catch (std::exception &err)
	{
		if (nullptr != errorSink)
		{
			errorSink(err.what(), errorSinkContext);
		}

		return WINNET_GTII_STATUS::FAILURE;
	}
	catch (...)
	{
		return WINNET_GTII_STATUS::FAILURE;
	}
}

extern "C"
WINNET_LINKAGE
bool
WINNET_API
WinNet_GetTapInterfaceAlias(
	wchar_t **alias,
	WinNetErrorSink errorSink,
	void *errorSinkContext
)
{
	try
	{
		const auto currentAlias = InterfaceUtils::GetTapInterfaceAlias();

		auto stringBuffer = new wchar_t[currentAlias.size() + 1];
		wcscpy(stringBuffer, currentAlias.c_str());

		*alias = stringBuffer;

		return true;
	}
	catch (std::exception &err)
	{
		if (nullptr != errorSink)
		{
			errorSink(err.what(), errorSinkContext);
		}

		return false;
	}
	catch (...)
	{
		return false;
	}
}

extern "C"
WINNET_LINKAGE
void
WINNET_API
WinNet_ReleaseString(
	wchar_t *str
)
{
	try
	{
		delete[] str;
	}
	catch (...)
	{
	}
}

extern "C"
WINNET_LINKAGE
bool
WINNET_API
WinNet_ActivateConnectivityMonitor(
	WinNetConnectivityMonitorCallback callback,
	void *callbackContext,
	bool *currentConnectivity,
	WinNetErrorSink errorSink,
	void *errorSinkContext
)
{
	try
	{
		if (nullptr != g_NetMonitor)
		{
			throw std::runtime_error("Cannot activate connectivity monitor twice");
		}

		auto forwarder = [callback, callbackContext](bool connected)
		{
			callback(connected, callbackContext);
		};

		bool connected = false;

		g_NetMonitor = new NetMonitor(forwarder, connected);

		if (nullptr != currentConnectivity)
		{
			*currentConnectivity = connected;
		}

		return true;
	}
	catch (std::exception &err)
	{
		if (nullptr != errorSink)
		{
			errorSink(err.what(), errorSinkContext);
		}

		return false;
	}
	catch (...)
	{
		return false;
	}
}

extern "C"
WINNET_LINKAGE
void
WINNET_API
WinNet_DeactivateConnectivityMonitor(
)
{
	try
	{
		delete g_NetMonitor;
		g_NetMonitor = nullptr;
	}
	catch (...)
	{
	}
}

extern "C"
WINNET_LINKAGE
WINNET_CC_STATUS
WINNET_API
WinNet_CheckConnectivity(
	WinNetErrorSink errorSink,
	void *errorSinkContext
)
{
	try
	{
		return (NetMonitor::CheckConnectivity() ? WINNET_CC_STATUS::CONNECTED : WINNET_CC_STATUS::NOT_CONNECTED);
	}
	catch (std::exception &err)
	{
		if (nullptr != errorSink)
		{
			errorSink(err.what(), errorSinkContext);
		}

		return WINNET_CC_STATUS::CONNECTIVITY_UNKNOWN;
	}
	catch (...)
	{
		return WINNET_CC_STATUS::CONNECTIVITY_UNKNOWN;
	}
}

extern "C"
WINNET_LINKAGE
bool
WINNET_API
WinNet_ActivateRouteManager(
	const WINNET_ROUTE *routes,
	uint32_t numRoutes,
	WinNetErrorSink errorSink,
	void *errorSinkContext
)
{
	try
	{
		if (nullptr != g_RouteManager)
		{
			throw std::runtime_error("Cannot activate route manager twice");
		}

		g_RouteManager = new RouteManager(ConvertRoutes(routes, numRoutes));

		return true;
	}
	catch (std::exception &err)
	{
		if (nullptr != errorSink)
		{
			errorSink(err.what(), errorSinkContext);
		}

		return false;
	}
	catch (...)
	{
		return false;
	}
}

extern "C"
WINNET_LINKAGE
void
WINNET_API
WinNet_DeactivateRouteManager(
)
{
	try
	{
		delete g_RouteManager;
		g_RouteManager = nullptr;
	}
	catch (...)
	{
	}
}
