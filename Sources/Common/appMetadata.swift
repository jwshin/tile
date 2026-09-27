public let stableAppId: String = "local.jwshin.tile"
#if DEBUG
    public let appId: String = "local.jwshin.tile.debug"
    public let appName: String = "tile-debug"
#else
    public let appId: String = stableAppId
    public let appName: String = "tile"
#endif
