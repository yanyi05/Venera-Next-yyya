import VisionKit
import ImageIO
import Flutter
import UIKit
import UniformTypeIdentifiers
import Foundation // 添加此行

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let directoryAccess = ScopedDirectoryAccess()
  private var directoryTerminationObserver: NSObjectProtocol?

  // 定义插件通道名称
  private var directoryPicker: DirectoryPicker?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    directoryTerminationObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willTerminateNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.directoryAccess.close() }

    guard let registrar = registrar(forPlugin: "VeneraPlatform") else {
      NSLog("VeneraNext: platform registrar unavailable at launch")
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    let methodChannel = FlutterMethodChannel(name: "venera/method_channel", binaryMessenger: registrar.messenger())
    methodChannel.setMethodCallHandler { (call, result) in
      if call.method == "getProxy" {
        if let proxySettings = CFNetworkCopySystemProxySettings()?.takeUnretainedValue() as NSDictionary?,
          let dict = proxySettings.object(forKey: kCFNetworkProxiesHTTPProxy) as? NSDictionary,
          let host = dict.object(forKey: kCFNetworkProxiesHTTPProxy) as? String,
          let port = dict.object(forKey: kCFNetworkProxiesHTTPPort) as? Int {
          let proxyConfig = "\(host):\(port)"
          result(proxyConfig)
        } else {
          result("")
        }
      } else if call.method == "setScreenOn" {
        if let arguments = call.arguments as? Bool {
          let screenOn = arguments
          UIApplication.shared.isIdleTimerDisabled = screenOn
        }
        result(nil)
      } else if call.method == "getDirectoryPath" {
        self.getDirectoryPath(result: result)
      } else if call.method == "imageTextAvailable" {
        if #available(iOS 16.0, *) { result(ImageAnalyzer.isSupported) }
        else { result(false) }
      } else if call.method == "analyzeImageText" {
        guard #available(iOS 16.0, *), ImageAnalyzer.isSupported else {
          result(FlutterError(code: "unsupported", message: "This device does not support Live Text", details: nil))
          return
        }
        guard let bytes = call.arguments as? FlutterStandardTypedData,
              let source = CGImageSourceCreateWithData(bytes.data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let presenter = self.window?.rootViewController,
              presenter.presentedViewController == nil else {
          result(FlutterError(code: "image_unavailable", message: "Cannot open image for text recognition", details: nil))
          return
        }
        let page = ReaderImageTextController(image: UIImage(cgImage: image), completion: result)
        let navigation = UINavigationController(rootViewController: page)
        navigation.modalPresentationStyle = .fullScreen
        presenter.present(navigation, animated: true)
      } else if call.method == "restoreDirectoryAccess" {
        result(self.directoryAccess.restorePersisted())
      } else if call.method == "releaseDirectoryAccess" || call.method == "retainDirectoryAccessForSession" {
        guard let token = call.arguments as? String else {
          result(FlutterError(code: "invalid_arguments", message: "Missing directory token", details: nil))
          return
        }
        do {
          if call.method == "releaseDirectoryAccess" {
            self.directoryAccess.release(token)
          } else {
            try self.directoryAccess.retainForSession(token)
          }
          result(nil)
        } catch {
          result(FlutterError(code: "directory_access", message: String(describing: error), details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func getDirectoryPath(result: @escaping FlutterResult) {
    guard directoryPicker == nil else {
      result(FlutterError(code: "picker_busy", message: "Directory picker is already open", details: nil))
      return
    }
    guard let presenter = window?.rootViewController, presenter.presentedViewController == nil else {
      result(FlutterError(code: "picker_unavailable", message: "No available directory picker presenter", details: nil))
      return
    }
    let picker = DirectoryPicker()
    directoryPicker = picker
    picker.selectDirectory(from: presenter) { [weak self] url in
      guard let self = self else {
        result(FlutterError(code: "picker_closed", message: "Directory picker owner closed", details: nil))
        return
      }
      self.directoryPicker = nil
      guard let url = url else { result(nil); return }
      do { result(try self.directoryAccess.acquire(url)) }
      catch { result(FlutterError(code: "directory_access", message: String(describing: error), details: nil)) }
    }
  }

}

@available(iOS 16.0, *)
private final class ReaderImageTextController: UIViewController, UIScrollViewDelegate {
  private let image: UIImage
  private let analyzer = ImageAnalyzer()
  private let interaction = ImageAnalysisInteraction()
  private let scrollView = UIScrollView()
  private let imageView = UIImageView()
  private let status = UILabel()
  private var analysisTask: Task<Void, Never>?
  private var completion: FlutterResult?

  init(image: UIImage, completion: @escaping FlutterResult) {
    self.image = image
    self.completion = completion
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { return nil }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = "识别文字与翻译"
    view.backgroundColor = .systemBackground
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .done, target: self, action: #selector(closePage))
    status.text = "正在识别…完成后长按文字，可选择复制或翻译。"
    status.numberOfLines = 0
    status.font = .preferredFont(forTextStyle: .footnote)
    status.adjustsFontForContentSizeCategory = true
    status.translatesAutoresizingMaskIntoConstraints = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.delegate = self
    scrollView.maximumZoomScale = 12
    view.addSubview(status)
    view.addSubview(scrollView)
    NSLayoutConstraint.activate([
      status.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      status.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      status.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 8),
      scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
    ])
    imageView.image = image
    imageView.contentMode = .scaleAspectFit
    imageView.isUserInteractionEnabled = true
    imageView.addInteraction(interaction)
    interaction.preferredInteractionTypes = .automatic
    scrollView.addSubview(imageView)
    analysisTask = Task { [weak self] in
      guard let self = self else { return }
      do {
        let analysis = try await self.analyzer.analyze(self.image,
          configuration: ImageAnalyzer.Configuration([.text]))
        guard !Task.isCancelled else { return }
        self.interaction.analysis = analysis
        self.status.text = analysis.hasResults(for: .text)
          ? "长按文字选择；在系统菜单中复制或翻译。可双指缩放查看。"
          : "未识别到文字。可尝试更清晰的图片；手写或艺术字可能无法识别。"
      } catch {
        guard !Task.isCancelled else { return }
        self.status.text = "识别失败，请关闭后重试。"
      }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if scrollView.zoomScale == 1 {
      imageView.frame = scrollView.bounds
      scrollView.contentSize = scrollView.bounds.size
    }
  }
  func viewForZooming(in scrollView: UIScrollView) -> UIView? { return imageView }
  @objc private func closePage() {
    analysisTask?.cancel()
    let callback = completion
    completion = nil
    dismiss(animated: true) { callback?(nil) }
  }
}
