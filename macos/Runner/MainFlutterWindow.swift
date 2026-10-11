import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    // It opens maximized: the whole screen but the menu bar and the Dock.
    self.setFrame(NSScreen.main?.visibleFrame ?? windowFrame, display: true)
    // No narrower than 960: below that, the player bar's middle buttons go past the ends of the seek bar under them
    // (NowPlayingBar; now_playing_bar_test.dart has the same width).
    self.contentMinSize = NSSize(width: 960, height: self.contentMinSize.height)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
