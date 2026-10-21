import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var iconChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "flutter_launchpad_host/macos_icons",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "getApplicationIcon" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String
      else {
        result(nil)
        return
      }
      result(MainFlutterWindow.pngIcon(forApplicationAt: path))
    }
    iconChannel = channel

    super.awakeFromNib()
  }

  private static func pngIcon(forApplicationAt path: String) -> FlutterStandardTypedData? {
    let icon = NSWorkspace.shared.icon(forFile: path)
    let pixelSize = 128
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    else {
      return nil
    }

    bitmap.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    icon.draw(
      in: NSRect(
        x: 0,
        y: 0,
        width: CGFloat(pixelSize),
        height: CGFloat(pixelSize)
      )
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
      return nil
    }
    return FlutterStandardTypedData(bytes: png)
  }
}
