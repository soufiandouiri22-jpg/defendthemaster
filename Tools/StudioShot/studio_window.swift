// Prints the window number of the open Roblox Studio place window, for `screencapture -l`.
import CoreGraphics

let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for w in windows {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    let name = w[kCGWindowName as String] as? String ?? ""
    let layer = w[kCGWindowLayer as String] as? Int ?? -1
    if owner.contains("Roblox") && layer == 0 && name.hasSuffix("- Roblox Studio") {
        print(w[kCGWindowNumber as String]!)
        break
    }
}
