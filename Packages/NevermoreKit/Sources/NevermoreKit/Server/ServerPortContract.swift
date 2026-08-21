import Foundation

/// The single source of truth for which loopback ports Nevermore's companion HTTP server may bind,
/// and that every client probes to find it.
///
/// The app server and the MCP bridge MUST both use this exact list, otherwise the server can end up
/// running on a port no client ever checks — "running but not found", which looks like a dead server
/// from the outside and a healthy one from the inside.
///
/// The server binds ONLY these fixed ports. There is deliberately no ephemeral fallback: an
/// OS-assigned port is undiscoverable by the bridge, so with all five taken the server fails closed
/// and surfaces the failure rather than listening somewhere nothing can reach it.
///
/// 8775–8779 is Nevermore's range. The sibling jobhunt app owns 8765–8769 and 8770–8774 is left as
/// its growth gap, so the two apps can run side by side on one Mac without a collision.
public enum ServerPortContract {
    public static let firstPort: UInt16 = 8775
    public static let lastPort: UInt16 = 8779

    /// All bindable/probed ports, in priority order.
    public static let discoveryPorts: [UInt16] = Array(firstPort ... lastPort)
}
