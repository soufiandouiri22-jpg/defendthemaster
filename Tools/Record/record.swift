// Records an app's largest window with that app's own sound (nothing else from the Mac, no microphone) to an MP4
// at 60 fps, until it gets SIGINT or SIGTERM. Built and run by record.sh.
// Usage: record <out.mp4> [app]   (app: part of the app's name or bundle id, default "Roblox")
//        record --list            (the windows it can record)
import AppKit
import AppKit
import AVFoundation
import Foundation
import ScreenCaptureKit

final class Recorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    var stream: SCStream?

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        print("recording")
        fflush(stdout)
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        fputs("recording failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        print("saved")
        exit(0)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fputs("capture stopped: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

    func stop() {
        guard let stream else { exit(0) }
        stream.stopCapture { _ in }
        // The file is written once the recording output reports it finished; give up if it never does.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            fputs("recording did not finish\n", stderr)
            exit(1)
        }
    }
}

func windows() async throws -> [SCWindow] {
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    return content.windows.filter { $0.windowLayer == 0 && $0.frame.width > 100 && $0.frame.height > 50 }
}

func matches(_ window: SCWindow, _ app: String) -> Bool {
    guard let owner = window.owningApplication else { return false }
    return owner.applicationName.localizedCaseInsensitiveContains(app)
        || owner.bundleIdentifier.localizedCaseInsensitiveContains(app)
}

// A window capture needs the window server connection that AppKit opens.
_ = NSApplication.shared
// A window filter needs the window server connection that AppKit opens, and macOS puts its recording sign in the menu
// bar, which needs AppKit's run loop on the main thread.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let recorder = Recorder()
let args = Array(CommandLine.arguments.dropFirst())

Task {
    do {
        if args.first == "--list" {
            for w in try await windows() {
                let owner = w.owningApplication
                print("\(owner?.applicationName ?? "?") (\(owner?.bundleIdentifier ?? "?")): \(w.title ?? "") "
                    + "\(Int(w.frame.width))x\(Int(w.frame.height))")
            }
            exit(0)
        }
        guard let out = args.first else {
            fputs("usage: record <out.mp4> [app] | record --list\n", stderr)
            exit(2)
        }
        let name = args.count > 1 ? args[1] : "Roblox"
        let found = try await windows().filter { matches($0, name) }
        guard let window = found.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        else {
            fputs("no window of \(name) on screen\n", stderr)
            exit(1)
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        // Even sizes: H.264 needs them.
        config.width = Int(window.frame.width * scale) / 2 * 2
        config.height = Int(window.frame.height * scale) / 2 * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 8
        config.showsCursor = false
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2

        let output = SCRecordingOutputConfiguration()
        output.outputURL = URL(fileURLWithPath: out)
        output.outputFileType = .mp4
        output.videoCodecType = .h264

        let stream = SCStream(filter: filter, configuration: config, delegate: recorder)
        try stream.addRecordingOutput(SCRecordingOutput(configuration: output, delegate: recorder))
        recorder.stream = stream
        try await stream.startCapture()
        let owner = window.owningApplication?.applicationName ?? name
        print("window: \(owner): \(window.title ?? "") \(config.width)x\(config.height)")
        fflush(stdout)
    } catch {
        fputs("could not record: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

var stops: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { recorder.stop() }
    source.resume()
    stops.append(source)
}
app.run()
