import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers
import WebKit

class MainFlutterWindow: NSWindow {
  private var logSaveChannel: FlutterMethodChannel?
  private var logSavePanel: NSSavePanel?
  private var loginCaptchaChannel: FlutterMethodChannel?
  private var loginCaptchaWindow: NeteaseCaptchaWindow?
  private var isHeadless: Bool {
    ProcessInfo.processInfo.arguments.dropFirst().first == "--headless"
  }

  override func awakeFromNib() {
    if isHeadless {
      super.awakeFromNib()
      return
    }

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerLogSavePanel(flutterViewController)
    registerLoginCaptcha(flutterViewController)

    super.awakeFromNib()
  }

  private func registerLoginCaptcha(_ controller: FlutterViewController) {
    let registrar = controller.registrar(forPlugin: "NeteaseLoginCaptcha")
    let channel = FlutterMethodChannel(name: "mcdev_income/login_captcha",
                                       binaryMessenger: registrar.messenger)
    loginCaptchaChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "verify" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let parent = self else {
        result(FlutterError(code: "no_window", message: "登录窗口已关闭。", details: nil))
        return
      }
      guard parent.loginCaptchaWindow == nil else {
        result(FlutterError(code: "captcha_busy", message: "请先完成当前验证码。", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any],
            let html = args["html"] as? String, html.utf8.count <= 100_000,
            let nonce = args["nonce"] as? String,
            nonce.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil else {
        result(FlutterError(code: "invalid_captcha", message: "验证码配置无效，请重新登录。", details: nil))
        return
      }
      let presenter = NeteaseCaptchaWindow(parent: parent, html: html, nonce: nonce) {
        [weak parent] reply in
        parent?.loginCaptchaWindow = nil
        result(reply)
      }
      parent.loginCaptchaWindow = presenter
      presenter.present()
    }
  }

  private func registerLogSavePanel(_ controller: FlutterViewController) {
    let registrar = controller.registrar(forPlugin: "DevelopmentLogSavePanel")
    let channel = FlutterMethodChannel(name: "mcdev_income/development_logs",
                                       binaryMessenger: registrar.messenger)
    logSaveChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "chooseLogExport" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let window = self else {
        result(FlutterError(code: "no_window", message: "日志窗口已关闭。", details: nil))
        return
      }
      guard window.logSavePanel == nil else {
        result(FlutterError(code: "save_in_progress", message: "请先完成当前导出。", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any],
            let fileName = args["fileName"] as? String, !fileName.isEmpty else {
        result(FlutterError(code: "invalid_filename", message: "日志文件名无效。", details: nil))
        return
      }
      let panel = NSSavePanel()
      window.logSavePanel = panel
      panel.title = (args["filtered"] as? Bool == true) ? "导出筛选结果" : "导出原始日志"
      panel.nameFieldStringValue = (fileName as NSString).lastPathComponent
      panel.canCreateDirectories = true
      panel.allowsOtherFileTypes = false
      if #available(macOS 11.0, *) {
        panel.allowedContentTypes = [UTType(filenameExtension: "log", conformingTo: .plainText)
                                    ?? .plainText, .plainText]
      } else {
        panel.allowedFileTypes = ["log", "txt"]
      }
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      panel.beginSheetModal(for: window) { [weak window] response in
        window?.logSavePanel = nil
        result(response == .OK ? panel.url?.path : nil)
      }
    }
  }

  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    if isHeadless && place != .out { return }
    super.order(place, relativeTo: otherWin)
  }
}

/// A temporary view of the official Yidun widget. It has no developer-platform
/// cookies, password field, browser controls, or access to the user's browser.
private final class NeteaseCaptchaWindow: NSObject, NSWindowDelegate,
                                          WKScriptMessageHandler, WKNavigationDelegate {
  private weak var parent: NSWindow?
  private let window: NSWindow
  private var webView: WKWebView?
  private let html: String
  private let nonce: String
  private var completion: ((Any?) -> Void)?
  private let baseURL = URL(string: "https://dl.reg.163.com/")!

  init(parent: NSWindow, html: String, nonce: String,
       completion: @escaping (Any?) -> Void) {
    self.parent = parent
    self.html = html
    self.nonce = nonce
    self.completion = completion
    self.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 540),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
    super.init()

    window.title = "网易人机验证"
    window.isReleasedWhenClosed = false
    window.delegate = self
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.userContentController.add(self, name: "mcdevCaptcha")
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 580, height: 540),
                         configuration: configuration)
    view.autoresizingMask = [.width, .height]
    view.navigationDelegate = self
    window.contentView = view
    webView = view
  }

  func present() {
    guard let parent = parent else {
      finish(nil)
      return
    }
    NSApp.activate(ignoringOtherApps: true)
    parent.makeKeyAndOrderFront(nil)
    parent.beginSheet(window) { [weak self] _ in self?.finish(nil) }
    webView?.loadHTMLString(html, baseURL: baseURL)
  }

  func windowWillClose(_ notification: Notification) {
    finish(nil)
  }

  func userContentController(_ userContentController: WKUserContentController,
                             didReceive message: WKScriptMessage) {
    guard completion != nil, message.name == "mcdevCaptcha", message.frameInfo.isMainFrame,
          let body = message.body as? [String: Any], body["nonce"] as? String == nonce,
          let type = body["type"] as? String else { return }
    switch type {
    case "verified":
      guard let proof = body["validate"] as? String,
            !proof.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            proof.utf8.count <= 16_384 else { return }
      finish(proof)
    case "cancel":
      finish(nil)
    case "reload":
      webView?.loadHTMLString(html, baseURL: baseURL)
    default:
      break
    }
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    guard let url = navigationAction.request.url else {
      decisionHandler(.cancel)
      return
    }
    // This is a captcha view, not a general browser or platform-login surface.
    if url.scheme == "about" {
      decisionHandler(.allow)
      return
    }
    if navigationAction.targetFrame?.isMainFrame != false {
      decisionHandler(url == baseURL ? .allow : .cancel)
      return
    }
    let host = url.host?.lowercased() ?? ""
    let trusted = ["163.com", "126.net", "127.net", "163yun.com"].contains {
      host == $0 || host.hasSuffix("." + $0)
    }
    decisionHandler(url.scheme == "https" && trusted ? .allow : .cancel)
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
               withError error: Error) {
    if (error as NSError).code == NSURLErrorCancelled { return }
    finish(FlutterError(code: "captcha_load_failed", message: "验证码加载失败，请重新登录后重试。",
                        details: nil))
  }

  private func finish(_ reply: Any?) {
    guard let callback = completion else { return }
    completion = nil
    webView?.stopLoading()
    webView?.configuration.userContentController.removeScriptMessageHandler(forName: "mcdevCaptcha")
    webView?.navigationDelegate = nil
    if window.sheetParent != nil { parent?.endSheet(window) }
    window.orderOut(nil)
    window.delegate = nil
    window.contentView = nil
    webView = nil
    callback(reply)
  }
}
