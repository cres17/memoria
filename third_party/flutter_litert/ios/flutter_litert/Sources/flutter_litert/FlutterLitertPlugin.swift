import Flutter
import UIKit
import flutter_litert_custom_ops
import flutter_litert_delegate_symbols

public class FlutterLitertPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    FlutterLitertRetainFfiSymbols()
    FlutterLitertRetainCustomOps()
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
