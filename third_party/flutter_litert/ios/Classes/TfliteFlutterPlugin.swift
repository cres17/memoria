import Flutter
import UIKit

public class FlutterLitertPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // Force load custom ops to prevent linker from stripping them
    TfliteCustomOpsLoader.loadCustomOps()
    // Dart FFI resolves LiteRT APIs through dlsym(RTLD_DEFAULT), so keep the
    // packaged framework symbols reachable in release/TestFlight builds.
    FlutterLitertRetainFfiSymbols()
    let channel = FlutterMethodChannel(name: "flutter_litert", binaryMessenger: registrar.messenger())
    let instance = FlutterLitertPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
