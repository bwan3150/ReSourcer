//
//  QRScannerView.swift
//  ReSourcer
//
//  二维码扫描组件
//

import SwiftUI
import AVFoundation

// MARK: - QR 扫描结果

/// 从服务器二维码解析出的连接信息
struct QRServerInfo {
    let serverURL: String
    let apiKey: String
}

// MARK: - QRScannerView

/// 二维码扫描视图
struct QRScannerView: View {

    let onScanned: (QRServerInfo) -> Void
    let onDismiss: () -> Void

    @State private var isAuthorized = false
    @State private var showPermissionAlert = false

    var body: some View {
        ZStack {
            if isAuthorized {
                // 相机预览
                QRCameraPreview(onCodeScanned: handleScannedCode)
                    .ignoresSafeArea()

                // 扫描框叠加层
                scanOverlay
            } else {
                // 无权限提示
                VStack(spacing: AppTheme.Spacing.lg) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("需要相机权限来扫描二维码")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Button("打开设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .foregroundStyle(.blue)
                }
            }

            // 关闭按钮
            VStack {
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .padding(AppTheme.Spacing.lg)
                }
                Spacer()
            }
        }
        .onAppear {
            checkCameraPermission()
        }
    }

    // MARK: - 扫描框叠加层

    private var scanOverlay: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height) * 0.65
            let rect = CGRect(
                x: (geometry.size.width - size) / 2,
                y: (geometry.size.height - size) / 2 - 40,
                width: size,
                height: size
            )

            ZStack {
                // 半透明遮罩（扫描框外部）
                Path { path in
                    path.addRect(geometry.frame(in: .local))
                    path.addRoundedRect(
                        in: rect,
                        cornerSize: CGSize(width: 16, height: 16)
                    )
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))

                // 扫描框四角
                scanCorners(rect: rect)

                // 提示文字
                Text("扫描服务器二维码")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .position(x: geometry.size.width / 2, y: rect.maxY + 40)
            }
        }
        .ignoresSafeArea()
    }

    /// 扫描框四角装饰
    private func scanCorners(rect: CGRect) -> some View {
        let length: CGFloat = 24
        let lineWidth: CGFloat = 3

        return ZStack {
            // 左上
            Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
            }
            .stroke(.white, lineWidth: lineWidth)

            // 右上
            Path { p in
                p.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
            }
            .stroke(.white, lineWidth: lineWidth)

            // 左下
            Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.maxY - length))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.minX + length, y: rect.maxY))
            }
            .stroke(.white, lineWidth: lineWidth)

            // 右下
            Path { p in
                p.move(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
            }
            .stroke(.white, lineWidth: lineWidth)
        }
    }

    // MARK: - Methods

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    isAuthorized = granted
                }
            }
        default:
            isAuthorized = false
        }
    }

    /// 解析二维码内容: http://{IP}:{PORT}/login.html?key={API_KEY}
    private func handleScannedCode(_ code: String) {
        guard let url = URL(string: code),
              let host = url.host,
              let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "key" })?.value
        else { return }

        let port = url.port.map { ":\($0)" } ?? ""
        let scheme = url.scheme ?? "http"
        let serverURL = "\(scheme)://\(host)\(port)"

        onScanned(QRServerInfo(serverURL: serverURL, apiKey: key))
    }
}

// MARK: - AVFoundation 相机预览

/// UIViewRepresentable 包装 AVCaptureSession
struct QRCameraPreview: UIViewRepresentable {

    let onCodeScanned: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black

        let session = AVCaptureSession()
        context.coordinator.session = session

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return view }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return view }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
        output.metadataObjectTypes = [.qr]

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.session?.stopRunning()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCodeScanned: (String) -> Void
        var session: AVCaptureSession?
        var previewLayer: AVCaptureVideoPreviewLayer?
        private var hasScanned = false

        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !hasScanned,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let code = object.stringValue
            else { return }

            // 只处理一次，防止重复回调
            hasScanned = true
            // 震动反馈
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            session?.stopRunning()
            onCodeScanned(code)
        }
    }
}
