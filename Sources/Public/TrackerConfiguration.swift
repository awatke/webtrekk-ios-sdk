import Foundation

public struct TrackerConfiguration {
	public var appVersion: String
	public var maxRequests: Int
	public var samplingRate: Int
	public var sendDelay = NSTimeInterval(5 * 60)
	public var version: Int
	public var optedOut: Bool

	public private(set) var serverUrl:  String
	public private(set) var trackingId: String

	public var autoTrack:                    Bool
	public var autoTrackAdvertiserId:        Bool
	public var autoTrackApiLevel:            Bool
	public var autoTrackAppUpdate:           Bool
	public var autoTrackAppVersionName:      Bool
	public var autoTrackAppVersionCode:      Bool
	public var autoTrackConnectionType:      Bool
	public var autoTrackRequestUrlStoreSize: Bool
	public var autoTrackScreenOrientation:   Bool
	public var autoTrackScreens:             [String: AutoTrackedScreen]

	public var enableRemoteConfiguration: Bool
	public var remoteConfigurationUrl:    String

	public private(set) var configFilePath: String

	public init?(configUrl: NSURL) {
		let defaultFileManager = NSFileManager.defaultManager()
		guard let path = configUrl.path where defaultFileManager.fileExistsAtPath(path) else {
			return nil
		}

		guard let xml = try? String(contentsOfURL: configUrl) else {
			return nil
		}

		guard let parser = try? XmlConfigParser(xmlString: xml) else {
			return nil
		}

		guard let config = parser.trackerConfiguration else {
			return nil
		}

		self.init(config: config)
	}


	private init(config: TrackerConfiguration) {
		self = config
	}

	
	public init(autoTrack: Bool = true,
	            autoTrackAdvertiserId: Bool = true,
	            autoTrackApiLevel: Bool = true,
	            autoTrackAppUpdate: Bool = true,
	            autoTrackAppVersionName: Bool = true,
	            autoTrackAppVersionCode: Bool = true,
	            autoTrackConnectionType: Bool = true,
	            autoTrackRequestUrlStoreSize: Bool = true,
	            autoTrackScreenOrientation: Bool = true,
	            autoTrackScreens: [String: AutoTrackedScreen] = [:],
	            appVersion: String = "",
	            configFilePath: String = "",
	            enableRemoteConfiguration: Bool = false,
	            maxRequests: Int = 1000,
	            optedOut: Bool = false,
	            remoteConfigurationUrl: String = "",
	            samplingRate: Int = 0,
	            sendDelay: NSTimeInterval = NSTimeInterval(5 * 60),
	            serverUrl: String,
	            trackingId: String,
	            version: Int = 0) {

		guard !serverUrl.isEmpty || !trackingId.isEmpty else {
			fatalError("Need serverUrl and trackingId for minimal Configuration")
		}

		guard let _ = NSURL(string: serverUrl) else {
			fatalError("serverUrl needs to be a valid url")
		}

		self.appVersion = appVersion
		self.maxRequests = maxRequests
		self.samplingRate = samplingRate
		self.sendDelay = sendDelay
		self.serverUrl = serverUrl
		self.trackingId = trackingId
		self.version = version
		self.optedOut = optedOut
		self.autoTrack = autoTrack
		self.autoTrackApiLevel = autoTrackApiLevel
		self.autoTrackAppUpdate = autoTrackAppUpdate
		self.autoTrackAdvertiserId = autoTrackAdvertiserId
		self.autoTrackAppVersionCode = autoTrackAppVersionCode
		self.autoTrackAppVersionName = autoTrackAppVersionName
		self.autoTrackConnectionType = autoTrackConnectionType
		self.autoTrackScreenOrientation = autoTrackScreenOrientation
		self.autoTrackScreens = autoTrackScreens
		self.autoTrackRequestUrlStoreSize = autoTrackRequestUrlStoreSize
		self.enableRemoteConfiguration = enableRemoteConfiguration
		self.remoteConfigurationUrl = remoteConfigurationUrl
		self.configFilePath = configFilePath
	}

}


internal extension TrackerConfiguration {

	internal var baseUrl: NSURL {
		get { return NSURL(string: serverUrl)!.URLByAppendingPathComponent(trackingId).URLByAppendingPathComponent("wt")}
	}
}



public struct AutoTrackedScreen: Equatable {
	public var className:             String
	public var mappingName:           String
	public var enabled:               Bool
	public var pageTracking: PageTracking?

	public init(className: String, mappingName: String, enabled: Bool = true, pageTracking: PageTracking? = nil) {
		self.className = className
		self.mappingName = mappingName
		self.enabled = enabled
		self.pageTracking = pageTracking
	}
}


public func ==(lhs: AutoTrackedScreen, rhs: AutoTrackedScreen) -> Bool {
	guard lhs.className == rhs.className else {
		return false
	}
	guard lhs.mappingName == rhs.mappingName else {
		return false
	}

	return true
}


extension AutoTrackedScreen: Hashable {
	public var hashValue: Int {
		get {
			return "\(className):\(mappingName)".hash
		}
	}
}