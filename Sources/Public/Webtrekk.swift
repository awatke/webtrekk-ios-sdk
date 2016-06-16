import UIKit
import ReachabilitySwift

public final class Webtrekk : Logable {

	public lazy var logger: Logger = DefaultLogger()

	public var advertisingIdentifier: (() -> String?)? {
		didSet {
			queue?.advertisingIdentifier = advertisingIdentifier
		}
	}

	public var enableLoging: Bool = false {
		didSet {
			guard oldValue != enableLoging else {
				return
			}
			logger.enabled = enableLoging
		}
	}

	public var config: TrackerConfiguration {
		didSet {
			guard oldValue.optedOut != config.optedOut else {
				return
			}
			queue?.shouldTrack = shouldTrack()

		}
	}

	public var flush: Bool = false{
		didSet {
			if flush {
				self.flush = false
				queue?.flushNow()
			}
		}
	}

	public var crossDeviceBridge: CrossDeviceBridgeParameter?

	private var plugins = [String: WebtrekkPlugin]()
	private var hibernationObserver: NSObjectProtocol?
	private var wakeUpObserver: NSObjectProtocol?
	private var queue: SendQueue?
	private lazy var fileManager: FileManager = FileManager(self.logger)

	// MARK: Lifecycle

	deinit {
		if let hibernationObserver = hibernationObserver {
			NSNotificationCenter.defaultCenter().removeObserver(hibernationObserver)
		}
		if let wakeUpObserver = wakeUpObserver {
			NSNotificationCenter.defaultCenter().removeObserver(wakeUpObserver)
		}
	}

	public convenience init(configParser: ConfigParser) throws {
		guard let config = configParser.trackerConfiguration else {
			throw WebtrekkError.InitParserError
		}
		self.init(config: config)
	}


	public init(config: TrackerConfiguration) {
		self.config = config
		setUp()
	}

	
	private func setUp() {
		setUpConfig()
		setUpQueue()
		setUpOptedOut()
	}


	private func setUpConfig() {
		// check if there is a local dump of the config saved
		if let localConfig = fileManager.restoreConfiguration(config.trackingId) where localConfig.version > config.version{
			self.config = localConfig
		}
		else {
			fileManager.saveConfiguration(config)
		}

		guard config.enableRemoteConfiguration && !config.remoteConfigurationUrl.isEmpty, let url = NSURL(string: config.remoteConfigurationUrl) else {
			return
		}

		guard !config.remoteConfigurationUrl.containsString("file://") else {
			if let xmlString = try? String(contentsOfURL: url), parser = try? XmlConfigParser(xmlString: xmlString), config = parser.trackerConfiguration {
				self.config = config
			}
			return
		}

		NSURLSession.get(url, logger: logger) { (data, error) -> Void in
			guard let xmlData = data else {
				self.log("No data could be retrieved from \(self.config.remoteConfigurationUrl).")
				return
			}
			guard let xmlString = String(data: xmlData, encoding: NSUTF8StringEncoding) else {
				self.log("Cannot parse data retreived from \(self.config.remoteConfigurationUrl)")
				return
			}

			let config: TrackerConfiguration!
			do {
				let parser = try XmlConfigParser(xmlString: xmlString)
				config = parser.trackerConfiguration
			} catch {
				self.log("\(WebtrekkError.RemoteParserError)")
				return
			}


			guard config.version > self.config.version else {
				self.log("Remote configuration is not newer then the currently used.")
				return
			}
			self.log("Updating tracker config from version \(self.config.version) to new version \(config.version)")
			self.config = config
			self.fileManager.saveConfiguration(config)
		}
	}


	private func setUpOptedOut() {
		config.optedOut =	NSUserDefaults.standardUserDefaults().boolForKey(UserStoreKey.OptedOut)
	}


	private func setUpQueue() {
		let backupFileUrl: NSURL = fileManager.getConfigurationDirectoryUrl(forTrackingId: config.trackingId).URLByAppendingPathComponent("queue.json")
		queue = SendQueue(backupFileUrl: backupFileUrl, sendDelay: config.sendDelay, maximumUrlCount: config.maxRequests, logger: logger)
		queue?.shouldTrack = shouldTrack()
	}


	func shouldTrack() -> Bool {
		let userDefaults = NSUserDefaults.standardUserDefaults()
		let userShouldBeSampled: Bool
		if let _ = userDefaults.objectForKey(UserStoreKey.Sampled.rawValue) {
			userShouldBeSampled = userDefaults.boolForKey(UserStoreKey.Sampled)
		}
		else {
			userShouldBeSampled = (config.samplingRate == 0) || (Int64(arc4random()) % Int64(config.samplingRate) == 0)
			userDefaults.setBool(userShouldBeSampled, forKey: UserStoreKey.Sampled.rawValue)
		}
		return userShouldBeSampled && !config.optedOut
	}

	// MARK: Tracking

	public func autoTrack(className: String) throws {
		guard config.autoTrack else {
			return
		}

		for (key, screen) in config.autoTrackScreens {
			guard className.containsString(key) else {
				continue
			}
			guard screen.enabled else {
				return
			}
			track(screen)
			return
		}
		track(className)
	}


	public func track(pageName: String) {
		track(PageTracking(pageName: pageName))
	}


	private func track(pageTracking: PageTracking) {
		var parameter = pageTracking
		parameter.generalParameter.firstStart = pageTracking.firstStart()
		enqueue(parameter, config: config)
	}


	public func track(pageName: String, trackingParameter: TrackingParameter) {
		var parameter = trackingParameter
		parameter.generalParameter.firstStart = trackingParameter.firstStart()
		if parameter.pixelParameter.pageName.isEmpty {
			parameter.pixelParameter.pageName = pageName
		}
		enqueue(parameter, config: config)
	}


	private func track(screen: AutoTrackedScreen) {
		if let pageTracking = screen.pageTracking {
			track(pageTracking)
		}
		else {
			track(screen.mappingName)
		}
	}


	private func enqueue(trackingParameter: TrackingParameter, config: TrackerConfiguration) {
		var enhancedTrackingParameter = trackingParameter
		enhancedTrackingParameter.generalParameter.samplingRate = config.samplingRate
		let parameter = handleBeforePluginCall(enhancedTrackingParameter)
		if shouldTrack() {
			var event = Event(trackingParameter: trackingParameter)
			var id: String? = nil
			if let advertisingIdentifier = advertisingIdentifier {
				id = advertisingIdentifier()
			}
			var count: Int = 0
			if let queue = queue {
				count = queue.itemCount
			}
			event.parse(config, advertisingIdentifier: id, itemCount: count)
			if let crossDeviceBridge = crossDeviceBridge {
				event.parse(crossDeviceBridge)
			}
			queue?.add(event)
		}
		handleAfterPluginCall(parameter)
	}

	
	public func trackerForScreen(screenName: String) -> ScreenTracker {
		let tracker = DefaultScreenTracker(webtrekk: self, logger: logger)
		tracker.updateWithName(screenName)
		return tracker
	}
}


public protocol WebtrekkPlugin: class {
	var id: String { get set }

	func beforeTrackingSend (parameter: TrackingParameter) -> TrackingParameter
	func afterTrackingSend  (parameter: TrackingParameter)
}


public enum WebtrekkError: ErrorType {
	case InitError
	case InitParserError
	case NoTrackerConfiguration
	case RemoteParserError
}


extension Webtrekk {

	// MARK: Plugins

	public func addPlugin(plugin: WebtrekkPlugin){
		guard let found = plugins[plugin.id] where found === plugin else {
			plugins[plugin.id] = plugin
			return
		}
		fatalError("The Plugin with the id:\"\(plugin.id)\" was already added.")
	}


	public func removePlugin(plugin: WebtrekkPlugin) -> Bool {
		guard let found = plugins.removeValueForKey(plugin.id) else {
			return false
		}
		return found === plugin
	}


	public func removeAllPlugins() -> Bool {
		plugins.removeAll()
		return plugins.isEmpty
	}


	internal func handleAfterPluginCall(trackingParameter: TrackingParameter) {
		guard !plugins.isEmpty else {
			return
		}

		for (_, plugin) in plugins {
			plugin.afterTrackingSend(trackingParameter)
		}
	}


	internal func handleBeforePluginCall(trackingParameter: TrackingParameter) -> TrackingParameter {
		guard !plugins.isEmpty else {
			return trackingParameter
		}
		var parameter = trackingParameter
		for (_, plugin) in plugins {
			parameter = plugin.beforeTrackingSend(parameter)
		}
		return parameter
	}
}