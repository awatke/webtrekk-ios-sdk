import AVFoundation
import AVKit

public /* final */ class WtAvPlayer: AVPlayer {
	internal var periodicObserver: AnyObject?
	internal var startObserver: AnyObject?
	internal var webtrekk: Webtrekk?
	internal var paused: Bool = true
	internal var startSeek: Float64 = 0
	internal var endSeek: Float64 = 0
	internal var mediaCategories: [Int: String] = [:]
	internal var logger: Logger?

	let periodicInterval = 30.0

	public convenience init(URL url: NSURL, webtrekk: Webtrekk, mediaCategories: [Int: String] = [:], logger: Logger? = nil) {
		self.init(playerItem: AVPlayerItem(asset: AVURLAsset(URL: url)), webtrekk: webtrekk, mediaCategories: mediaCategories, logger: logger)
	}


	public convenience init(playerItem item: AVPlayerItem, webtrekk: Webtrekk, mediaCategories: [Int: String] = [:], logger: Logger? = nil) {
		self.init(playerItem: item)
		self.webtrekk = webtrekk
		self.mediaCategories = mediaCategories
		self.logger = logger
		configureAVPlayer()
	}

	deinit{
		removeObserver(self, forKeyPath: "rate")
		if let periodicObserver = periodicObserver {
			removeTimeObserver(periodicObserver)
			self.periodicObserver = nil
		}
		if let startObserver = startObserver {
			removeTimeObserver(startObserver)
			self.startObserver = nil
		}
	}

	func configureAVPlayer() {
		addObserver(self, forKeyPath: "rate", options: [.New], context: nil)
		periodicObserver = addPeriodicTimeObserverForInterval(CMTime(seconds: periodicInterval, preferredTimescale: 1), queue: dispatch_get_main_queue()) { (time: CMTime) in
			guard self.error == nil else {
				self.logger?.log("error occured: \(self.error)", logLevel: .Error)
				return
			}

			if self.rate != 0{
				guard self.paused else {
					if	Int(CMTimeGetSeconds(time)) != 0 && Int(CMTimeGetSeconds(time)) % Int(self.periodicInterval) == 0, let mediaParameter = self.prepareMediaParameter(time, action: .Position) {
						self.webtrekk?.track(mediaParameter.name, trackingParameter: MediaTracking(mediaParameter: mediaParameter))
					}
					return
				}
				if self.startSeek != self.endSeek {
					if let mediaParameter = self.prepareMediaParameter(time, action: .Seek) {
						self.webtrekk?.track(mediaParameter.name, trackingParameter: MediaTracking(mediaParameter: mediaParameter))
					}
					self.startSeek = self.endSeek
				}
				self.paused = false
				if let mediaParameter = self.prepareMediaParameter(time) {
					self.webtrekk?.track(mediaParameter.name, trackingParameter: MediaTracking(mediaParameter: mediaParameter))
				}
			}
			else {
				if self.paused {
					self.endSeek = CMTimeGetSeconds(time)
				}
				else {
					self.paused = true
					self.startSeek = CMTimeGetSeconds(time)
					self.endSeek = CMTimeGetSeconds(time)
					if let mediaParameter = self.prepareMediaParameter(time, action: .Pause) {
						self.webtrekk?.track(mediaParameter.name, trackingParameter: MediaTracking(mediaParameter: mediaParameter))
					}
				}

			}
		}
	}

	private func prepareMediaParameter(pos: CMTime, action: MediaAction = .Play) -> MediaParameter? {
		guard let item = currentItem else {
			return nil
		}
		let name: String
		if let asset = item.asset as? AVURLAsset, let fileName = asset.URL.lastPathComponent {
			name = fileName
		}
		else {
			name = "generalMediaFile"
		}

		var mediaParameter = MediaParameter(action: action, duration: Int(CMTimeGetSeconds(item.duration)), name: name, position: Int(CMTimeGetSeconds(pos)))

		// bandwidth
		if item.tracks.count == 1 {
			mediaParameter.bandwidth = Int(item.tracks[0].assetTrack.estimatedDataRate)
		}
		else if item.tracks.count > 1 {
			var bandwith = -1
			for track in item.tracks where track.assetTrack.mediaType == AVMediaTypeVideo {
				bandwith = Int(track.assetTrack.estimatedDataRate) > bandwith ? Int(track.assetTrack.estimatedDataRate) : bandwith
			}
			mediaParameter.bandwidth = bandwith > 0 ? bandwith : nil
		}
		let volume = AVAudioSession.sharedInstance().outputVolume
		mediaParameter.mute = volume == 0
		mediaParameter.volume = Int(volume * 100)
		mediaParameter.categories = mediaCategories
		return mediaParameter
	}


	override public func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
		guard keyPath == "rate" else {
			return
		}

		guard let currentItem = self.currentItem where currentItem.currentTime() == currentItem.duration else {
			return
		}

		if let mediaParameter = self.prepareMediaParameter(currentItem.currentTime(), action: .EndOfFile) {
			self.webtrekk?.track(mediaParameter.name, trackingParameter: MediaTracking(mediaParameter: mediaParameter))
		}
	}
}