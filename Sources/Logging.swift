import Foundation


#if DEBUG
	public var logEnabled = true
#else
	public var logEnabled = false
#endif


public func log(@autoclosure messageClosure: Void throws -> String, function: StaticString = __FUNCTION__, file: StaticString = __FILE__, line: UInt = __LINE__) rethrows {
	if !logEnabled {
		return
	}

	let message = try messageClosure()
	let fileName = (file.stringValue as NSString).lastPathComponent

	logWithoutContext("\(message) \t\t\t// \(fileName):\(line) in \(function.stringValue)")
}


public func logWithoutContext(@autoclosure messageClosure: Void throws -> String) rethrows {
	if !logEnabled {
		return
	}

	NSLog("%@", "\(try messageClosure())")
}