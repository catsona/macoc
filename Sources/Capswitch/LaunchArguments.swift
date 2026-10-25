public enum LaunchArguments: Equatable {
    case application
    case doctor
    case install
    case waitForParent(Int32)

    public init(arguments: [String]) {
        if arguments.contains("--doctor") {
            self = .doctor
        } else if arguments.contains("--install") {
            self = .install
        } else if let rawValue = arguments.first(where: {
            $0.hasPrefix("--wait-for-pid=")
        })?.dropFirst("--wait-for-pid=".count),
                  let pid = Int32(rawValue), pid > 1 {
            self = .waitForParent(pid)
        } else {
            self = .application
        }
    }
}
