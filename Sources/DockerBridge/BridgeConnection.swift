import Foundation

struct BridgeConnection: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var sshUser: String
    var host: String
    var sshPort: Int
    var remotePort: Int
    var container: String
    var network: String
    var bindAddress: String
    var localPort: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        sshUser: String,
        host: String,
        sshPort: Int = 22,
        remotePort: Int,
        container: String,
        network: String,
        bindAddress: String,
        localPort: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sshUser = sshUser
        self.host = host
        self.sshPort = sshPort
        self.remotePort = remotePort
        self.container = container
        self.network = network
        self.bindAddress = bindAddress
        self.localPort = localPort
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case sshUser
        case host
        case sshPort
        case remotePort
        case container
        case network
        case bindAddress
        case localPort
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date()
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        sshUser = try container.decodeIfPresent(String.self, forKey: .sshUser) ?? ""
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        sshPort = try container.decodeIfPresent(Int.self, forKey: .sshPort) ?? 22
        remotePort = try container.decodeIfPresent(Int.self, forKey: .remotePort) ?? 5432
        self.container = try container.decodeIfPresent(String.self, forKey: .container) ?? ""
        network = try container.decodeIfPresent(String.self, forKey: .network) ?? ""
        bindAddress = try container.decodeIfPresent(String.self, forKey: .bindAddress) ?? "127.0.0.1"
        localPort = try container.decodeIfPresent(Int.self, forKey: .localPort) ?? 15432
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    static func defaultConnection() -> BridgeConnection {
        BridgeConnection(
            name: "Example Tunnel",
            sshUser: "ssh-user",
            host: "server.example.com",
            sshPort: 22,
            remotePort: 5432,
            container: "app-container",
            network: "docker-network",
            bindAddress: "127.0.0.1",
            localPort: 15432
        )
    }

    var localEndpoint: String {
        "\(bindAddress):\(localPort)"
    }

    var remoteEndpoint: String {
        "\(container):\(remotePort)"
    }

    var sshEndpoint: String {
        "\(sshUser)@\(host.lowercased()):\(sshPort)"
    }

    var menuDetail: String {
        "\(localEndpoint) -> \(sshEndpoint)/\(container)"
    }

    func scriptArguments() -> [String] {
        [
            "-u", sshUser,
            "-H", host.lowercased(),
            "-P", String(sshPort),
            "-p", String(remotePort),
            "-c", container,
            "-n", network,
            "-b", bindAddress,
            "-l", String(localPort)
        ]
    }
}
