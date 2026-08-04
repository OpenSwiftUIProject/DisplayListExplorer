import DisplayListDescription
import JavaScriptKit

final class DisplayListCanvasRenderer {
    private let surface: JSObject
    private let canvas: JSObject
    private let emptyState: JSObject
    private let summary: JSObject
    private let zoomOutButton: JSObject
    private let zoomValueButton: JSObject
    private let zoomInButton: JSObject
    private let fitButton: JSObject
    private let scaleIndicator: JSObject
    private let scaleLabel: JSObject
    private let scaleRule: JSObject
    private var preview: DisplayListPreview?
    private var device = PreviewDevice.iPhone17Pro
    private var manualScale: Double?
    private var renderedScale: Double?
    private var panOffsetX = 0.0
    private var panOffsetY = 0.0
    private var lastPanPoint: (x: Double, y: Double)?

    init(
        surface: JSObject,
        canvas: JSObject,
        emptyState: JSObject,
        summary: JSObject,
        zoomOutButton: JSObject,
        zoomValueButton: JSObject,
        zoomInButton: JSObject,
        fitButton: JSObject,
        scaleIndicator: JSObject,
        scaleLabel: JSObject,
        scaleRule: JSObject
    ) {
        self.surface = surface
        self.canvas = canvas
        self.emptyState = emptyState
        self.summary = summary
        self.zoomOutButton = zoomOutButton
        self.zoomValueButton = zoomValueButton
        self.zoomInButton = zoomInButton
        self.fitButton = fitButton
        self.scaleIndicator = scaleIndicator
        self.scaleLabel = scaleLabel
        self.scaleRule = scaleRule
        updateScaleInterface()
    }

    func show(_ preview: DisplayListPreview) {
        self.preview = preview
        let layers = layerCount(in: preview.items)
        let approximationCount = preview.approximations.count
        summary.textContent = .string(
            approximationCount == 0
                ? "\(layers) visible layers"
                : "\(layers) visible layers · \(approximationCount) approximation types"
        )
        emptyState.hidden = .boolean(true)
        redraw()
    }

    func showEmpty(_ message: String, summary summaryText: String = "No preview") {
        preview = nil
        summary.textContent = .string(summaryText)
        emptyState.textContent = .string(message)
        emptyState.hidden = .boolean(false)
        renderedScale = nil
        lastPanPoint = nil
        updateScaleInterface()
        clearCanvas()
    }

    func selectDevice(
        _ identifier: String,
        windowWidth: Double,
        windowHeight: Double
    ) {
        let nextDevice = PreviewDevice(
            identifier: identifier,
            windowWidth: windowWidth,
            windowHeight: windowHeight
        )
        guard nextDevice != device else { return }
        device = nextDevice
        manualScale = nil
        resetPan()
        redraw()
    }

    func zoomIn() {
        zoom(by: 1.41421356237)
    }

    func zoomOut() {
        zoom(by: 1 / 1.41421356237)
    }

    func showActualSize() {
        guard preview != nil else { return }
        manualScale = 1
        resetPan()
        redraw()
    }

    func fitToSurface() {
        guard preview != nil else { return }
        manualScale = nil
        resetPan()
        redraw()
    }

    func beginPan(x: Double, y: Double) -> Bool {
        guard preview != nil, renderedScale != nil else { return false }
        lastPanPoint = (x, y)
        return true
    }

    func updatePan(x: Double, y: Double) {
        guard let lastPanPoint else { return }
        panOffsetX += x - lastPanPoint.x
        panOffsetY += y - lastPanPoint.y
        self.lastPanPoint = (x, y)
        redraw()
    }

    func endPan() {
        lastPanPoint = nil
    }

    func redraw() {
        guard let preview,
              let context = canvas.getContext!("2d").object,
              bounds(of: preview.items, origin: .zero) != nil else {
            if preview != nil {
                showEmpty(
                    "This DisplayList has no renderable frames.",
                    summary: "No visible layers"
                )
            }
            return
        }

        let width = Double(surface.clientWidth.number ?? 0)
        let height = Double(surface.clientHeight.number ?? 0)
        guard width > 0, height > 0 else { return }

        let deviceScale = max(1, min(3, JSObject.global.window.devicePixelRatio.number ?? 1))
        canvas.width = .number((width * deviceScale).rounded())
        canvas.height = .number((height * deviceScale).rounded())

        _ = context.setTransform!(deviceScale, 0, 0, deviceScale, 0, 0)
        _ = context.clearRect!(0, 0, width, height)

        let viewportPadding = 32.0
        let availableWidth = max(1, width - viewportPadding * 2)
        let availableHeight = max(1, height - viewportPadding * 2)
        let stageBounds = device.stageBounds
        let fitScale = max(
            0.01,
            min(
                4,
                min(
                    availableWidth / max(stageBounds.width, 1),
                    availableHeight / max(stageBounds.height, 1)
                )
            )
        )
        let scale = min(16, max(0.01, manualScale ?? fitScale))
        renderedScale = scale
        updateScaleInterface()
        let stageWidth = stageBounds.width * scale
        let stageHeight = stageBounds.height * scale
        let offsetX = (width - stageWidth) * 0.5 - stageBounds.minX * scale + panOffsetX
        let offsetY = (height - stageHeight) * 0.5 - stageBounds.minY * scale + panOffsetY

        _ = context.save!()
        _ = context.transform!(scale, 0, 0, scale, offsetX, offsetY)

        drawDeviceBackground(device, scale: scale, in: context)
        _ = context.save!()
        traceRoundedRect(device.screenBounds, radius: device.screenCornerRadius, in: context)
        _ = context.clip!()
        draw(preview.items, in: context)
        _ = context.restore!()
        drawDeviceOverlay(device, scale: scale, in: context)
        _ = context.restore!()
    }

    private func zoom(by factor: Double) {
        guard preview != nil, let renderedScale else { return }
        manualScale = min(16, max(0.01, renderedScale * factor))
        redraw()
    }

    private func resetPan() {
        panOffsetX = 0
        panOffsetY = 0
        lastPanPoint = nil
    }

    private func updateScaleInterface() {
        let hasPreview = renderedScale != nil
        zoomOutButton.disabled = .boolean(!hasPreview || (renderedScale ?? 0) <= 0.010001)
        zoomValueButton.disabled = .boolean(!hasPreview)
        zoomInButton.disabled = .boolean(!hasPreview || (renderedScale ?? 0) >= 15.999)
        fitButton.disabled = .boolean(!hasPreview)

        let isFitted = manualScale == nil
        fitButton.ariaPressed = .string(isFitted ? "true" : "false")
        _ = fitButton.classList.toggle("is-active", isFitted)

        guard let renderedScale else {
            zoomValueButton.textContent = "—"
            zoomValueButton.ariaLabel = "Preview scale unavailable"
            scaleIndicator.hidden = .boolean(true)
            return
        }

        let percentage = formattedPercentage(renderedScale)
        zoomValueButton.textContent = .string("\(percentage)%")
        zoomValueButton.ariaLabel = .string(
            "Preview scale \(percentage) percent. Reset to 100 percent"
        )

        let measurement = scaleMeasurement(for: renderedScale)
        let label = formattedPoints(measurement.points)
        scaleLabel.textContent = .string("\(label) pt")
        scaleRule.style.width = .string("\(measurement.pixelWidth)px")
        scaleIndicator.ariaLabel = .string(
            "Scale ruler: \(label) DisplayList points"
        )
        scaleIndicator.hidden = .boolean(false)
    }

    private func formattedPercentage(_ scale: Double) -> String {
        let percentage = scale * 100
        if percentage >= 10 {
            return String(Int(percentage.rounded()))
        }
        let rounded = (percentage * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(rounded)
    }

    private func formattedPoints(_ points: Double) -> String {
        points == points.rounded() ? String(Int(points)) : String(points)
    }

    private func scaleMeasurement(for scale: Double) -> (points: Double, pixelWidth: Double) {
        let candidates = [
            0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500,
            1_000, 2_000, 5_000, 10_000, 20_000, 50_000, 100_000,
        ]
        let targetWidth = 72.0
        let points = candidates.min {
            abs($0 * scale - targetWidth) < abs($1 * scale - targetWidth)
        } ?? 100
        return (points, points * scale)
    }

    private func drawDeviceBackground(
        _ device: PreviewDevice,
        scale: Double,
        in context: JSObject
    ) {
        let screen = device.screenBounds
        _ = context.save!()
        context.shadowColor = .string("rgba(23, 32, 51, 0.24)")
        context.shadowBlur = .number(22 / scale)
        context.shadowOffsetY = .number(10 / scale)

        switch device {
        case .iPhone17Pro, .iPhone17ProMax, .iPhoneAir, .iPhone16e, .iPhone15Pro:
            let shell = PreviewBounds(
                minX: -8,
                minY: -8,
                maxX: screen.maxX + 8,
                maxY: screen.maxY + 8
            )
            traceRoundedRect(shell, radius: 63, in: context)
            context.fillStyle = .string("#15171a")
            _ = context.fill!()

            context.shadowColor = .string("transparent")
            traceRoundedRect(screen, radius: device.screenCornerRadius, in: context)
            context.fillStyle = .string("#ffffff")
            _ = context.fill!()
        case .window:
            let windowShell = PreviewBounds(
                minX: -8,
                minY: -38,
                maxX: screen.maxX + 8,
                maxY: screen.maxY + 8
            )
            traceRoundedRect(windowShell, radius: 12, in: context)
            context.fillStyle = .string("#d8dce3")
            _ = context.fill!()

            context.shadowColor = .string("transparent")
            context.fillStyle = .string("#f3f4f6")
            _ = context.fillRect!(0, -30, screen.width, 30)

            traceRoundedRect(screen, radius: device.screenCornerRadius, in: context)
            context.fillStyle = .string("#ffffff")
            _ = context.fill!()
        }

        _ = context.restore!()
    }

    private func drawDeviceOverlay(
        _ device: PreviewDevice,
        scale: Double,
        in context: JSObject
    ) {
        let screen = device.screenBounds
        _ = context.save!()

        switch device {
        case .iPhone17Pro, .iPhone17ProMax, .iPhoneAir, .iPhone16e, .iPhone15Pro:
            let topCutout = device.hasDynamicIsland
                ? PreviewBounds(
                    minX: (screen.width - 126) * 0.5,
                    minY: 11,
                    maxX: (screen.width + 126) * 0.5,
                    maxY: 48
                )
                : PreviewBounds(
                    minX: (screen.width - 164) * 0.5,
                    minY: -8,
                    maxX: (screen.width + 164) * 0.5,
                    maxY: 31
                )
            traceRoundedRect(topCutout, radius: device.hasDynamicIsland ? 19 : 13, in: context)
            context.fillStyle = .string("#050506")
            _ = context.fill!()

            let homeIndicator = PreviewBounds(
                minX: (screen.width - 140) * 0.5,
                minY: screen.height - 14,
                maxX: (screen.width + 140) * 0.5,
                maxY: screen.height - 9
            )
            traceRoundedRect(homeIndicator, radius: 2.5, in: context)
            context.fillStyle = .string("rgba(8, 10, 12, 0.82)")
            _ = context.fill!()
        case .window:
            for (x, color) in [(15.0, "#ff5f57"), (35.0, "#febc2e"), (55.0, "#28c840")] {
                _ = context.beginPath!()
                _ = context.arc!(x, -15, 6, 0, Double.pi * 2)
                context.fillStyle = .string(color)
                _ = context.fill!()
            }

            context.strokeStyle = .string("rgba(23, 32, 51, 0.14)")
            context.lineWidth = .number(1 / scale)
            _ = context.beginPath!()
            _ = context.moveTo!(0, 0)
            _ = context.lineTo!(screen.maxX, 0)
            _ = context.stroke!()
        }

        traceRoundedRect(screen, radius: device.screenCornerRadius, in: context)
        context.strokeStyle = .string(
            device.isPhone ? "rgba(255, 255, 255, 0.22)" : "rgba(23, 32, 51, 0.14)"
        )
        context.lineWidth = .number(1 / scale)
        _ = context.stroke!()
        _ = context.restore!()
    }

    private func traceRoundedRect(
        _ bounds: PreviewBounds,
        radius: Double,
        in context: JSObject
    ) {
        let radius = max(0, min(radius, min(bounds.width, bounds.height) * 0.5))
        _ = context.beginPath!()
        _ = context.moveTo!(bounds.minX + radius, bounds.minY)
        _ = context.lineTo!(bounds.maxX - radius, bounds.minY)
        _ = context.quadraticCurveTo!(bounds.maxX, bounds.minY, bounds.maxX, bounds.minY + radius)
        _ = context.lineTo!(bounds.maxX, bounds.maxY - radius)
        _ = context.quadraticCurveTo!(bounds.maxX, bounds.maxY, bounds.maxX - radius, bounds.maxY)
        _ = context.lineTo!(bounds.minX + radius, bounds.maxY)
        _ = context.quadraticCurveTo!(bounds.minX, bounds.maxY, bounds.minX, bounds.maxY - radius)
        _ = context.lineTo!(bounds.minX, bounds.minY + radius)
        _ = context.quadraticCurveTo!(bounds.minX, bounds.minY, bounds.minX + radius, bounds.minY)
        _ = context.closePath!()
    }

    private func clearCanvas() {
        guard let context = canvas.getContext!("2d").object else { return }
        let width = Double(surface.clientWidth.number ?? 0)
        let height = Double(surface.clientHeight.number ?? 0)
        let deviceScale = max(1, min(3, JSObject.global.window.devicePixelRatio.number ?? 1))
        canvas.width = .number((width * deviceScale).rounded())
        canvas.height = .number((height * deviceScale).rounded())
        _ = context.setTransform!(deviceScale, 0, 0, deviceScale, 0, 0)
        _ = context.clearRect!(0, 0, width, height)
    }

    private func draw(_ items: [DisplayListPreviewItem], in context: JSObject) {
        for item in items {
            _ = context.save!()
            _ = context.translate!(item.frame.x, item.frame.y)

            switch item.value {
            case .empty:
                break
            case let .content(content):
                draw(content, frame: item.frame, in: context)
            case let .effect(effect, children):
                apply(effect, in: context)
                draw(children, in: context)
            case let .states(children):
                draw(children, in: context)
            }

            _ = context.restore!()
        }
    }

    private func draw(
        _ content: DisplayListPreviewContent,
        frame: DisplayListPreviewRect,
        in context: JSObject
    ) {
        let width = max(0, frame.width)
        let height = max(0, frame.height)
        guard width > 0, height > 0 || isFlattened(content) else { return }

        switch content {
        case let .color(color):
            context.fillStyle = .string(color)
            _ = context.fillRect!(0, 0, width, height)
        case let .text(text, recordedSize):
            _ = context.save!()
            _ = context.beginPath!()
            _ = context.rect!(0, 0, width, height)
            _ = context.clip!()
            let textWidth = recordedSize.width > 0 ? recordedSize.width : width
            let textHeight = recordedSize.height > 0 ? recordedSize.height : height
            let fontSize = inferredSystemFontPointSize(
                for: text,
                width: textWidth,
                height: textHeight,
                in: context
            )
            context.fillStyle = .string("#172033")
            context.font = .string("400 \(fontSize)px -apple-system, BlinkMacSystemFont, sans-serif")
            context.textAlign = .string("center")
            context.textBaseline = .string("middle")
            _ = context.fillText!(text, width * 0.5, height * 0.5, width)
            _ = context.restore!()
        case .image:
            drawImagePlaceholder(width: width, height: height, in: context)
        case let .shape(path, color, evenOdd):
            _ = context.save!()
            _ = context.beginPath!()
            _ = context.rect!(0, 0, width, height)
            _ = context.clip!()
            trace(path, in: context)
            context.fillStyle = .string(color ?? "#635bff")
            _ = context.fill!(evenOdd ? "evenodd" : "nonzero")
            _ = context.restore!()
        case let .shadow(path, style):
            _ = context.save!()
            _ = context.beginPath!()
            _ = context.rect!(-style.radius * 3, -style.radius * 3, width + style.radius * 6, height + style.radius * 6)
            _ = context.clip!()
            trace(path, in: context)
            context.fillStyle = .string("rgba(0, 0, 0, 0.02)")
            context.shadowColor = .string(style.color)
            context.shadowBlur = .number(style.radius)
            context.shadowOffsetX = .number(style.offset.x)
            context.shadowOffsetY = .number(style.offset.y)
            _ = context.fill!()
            _ = context.restore!()
        case let .placeholder(label):
            drawPlaceholder(label, width: width, height: height, in: context)
        case let .flattened(origin, items):
            _ = context.save!()
            _ = context.translate!(origin.x, origin.y)
            draw(items, in: context)
            _ = context.restore!()
        }
    }

    private func apply(_ effect: DisplayListPreviewEffect, in context: JSObject) {
        switch effect {
        case .identity:
            break
        case let .opacity(opacity):
            let current = context.globalAlpha.number ?? 1
            context.globalAlpha = .number(current * opacity)
        case let .blendMode(mode):
            context.globalCompositeOperation = .string(mode)
        case let .clip(path, evenOdd):
            trace(path, in: context)
            _ = context.clip!(evenOdd ? "evenodd" : "nonzero")
        case let .transform(transform):
            _ = context.transform!(
                transform.a,
                transform.b,
                transform.c,
                transform.d,
                transform.tx,
                transform.ty
            )
        case let .filter(filter):
            context.filter = .string(filter)
        }
    }

    private func trace(_ path: DisplayListPreviewPath, in context: JSObject) {
        _ = context.beginPath!()
        for command in path.commands {
            switch command {
            case let .move(point):
                _ = context.moveTo!(point.x, point.y)
            case let .line(point):
                _ = context.lineTo!(point.x, point.y)
            case let .quad(control, end):
                _ = context.quadraticCurveTo!(control.x, control.y, end.x, end.y)
            case let .cubic(control1, control2, end):
                _ = context.bezierCurveTo!(
                    control1.x,
                    control1.y,
                    control2.x,
                    control2.y,
                    end.x,
                    end.y
                )
            case .close:
                _ = context.closePath!()
            }
        }
    }

    private func drawImagePlaceholder(width: Double, height: Double, in context: JSObject) {
        drawPlaceholder("Image", width: width, height: height, in: context, showLabel: false)

        let inset = max(3, min(width, height) * 0.14)
        let iconWidth = max(0, width - inset * 2)
        let iconHeight = max(0, height - inset * 2)
        guard iconWidth >= 12, iconHeight >= 12 else { return }

        context.strokeStyle = .string("#778399")
        context.lineWidth = .number(max(1, min(width, height) * 0.025))
        _ = context.strokeRect!(inset, inset, iconWidth, iconHeight)

        _ = context.beginPath!()
        _ = context.moveTo!(inset + iconWidth * 0.1, inset + iconHeight * 0.82)
        _ = context.lineTo!(inset + iconWidth * 0.38, inset + iconHeight * 0.5)
        _ = context.lineTo!(inset + iconWidth * 0.55, inset + iconHeight * 0.68)
        _ = context.lineTo!(inset + iconWidth * 0.72, inset + iconHeight * 0.42)
        _ = context.lineTo!(inset + iconWidth * 0.92, inset + iconHeight * 0.82)
        _ = context.stroke!()

        _ = context.beginPath!()
        _ = context.arc!(
            inset + iconWidth * 0.72,
            inset + iconHeight * 0.25,
            max(1.5, min(iconWidth, iconHeight) * 0.075),
            0,
            Double.pi * 2
        )
        context.fillStyle = .string("#778399")
        _ = context.fill!()
    }

    private func inferredSystemFontPointSize(
        for text: String,
        width: Double,
        height: Double,
        in context: JSObject
    ) -> Double {
        guard !text.isEmpty, width > 0, height > 0 else { return 13 }

        // Canvas logical pixels correspond to DisplayList layout points. Fit the
        // recorded text size using the default macOS system font and its usual
        // line-height ratio, rather than treating the item height as the font size.
        var lowerBound = 4.0
        var upperBound = max(lowerBound, min(96, height / 1.18))
        for _ in 0..<12 {
            let candidate = (lowerBound + upperBound) * 0.5
            context.font = .string("400 \(candidate)px -apple-system, BlinkMacSystemFont, sans-serif")
            let measuredWidth = context.measureText!(text).object?.width.number ?? .infinity
            if measuredWidth <= width {
                lowerBound = candidate
            } else {
                upperBound = candidate
            }
        }
        return lowerBound
    }

    private func drawPlaceholder(
        _ label: String,
        width: Double,
        height: Double,
        in context: JSObject,
        showLabel: Bool = true
    ) {
        context.fillStyle = .string("#eef1f5")
        _ = context.fillRect!(0, 0, width, height)

        _ = context.save!()
        _ = context.beginPath!()
        _ = context.rect!(0, 0, width, height)
        _ = context.clip!()
        context.strokeStyle = .string("rgba(105, 115, 134, 0.16)")
        context.lineWidth = .number(1)
        let spacing = max(10, min(width, height) * 0.22)
        var offset = -height
        while offset < width {
            _ = context.beginPath!()
            _ = context.moveTo!(offset, height)
            _ = context.lineTo!(offset + height, 0)
            _ = context.stroke!()
            offset += spacing
        }
        _ = context.restore!()

        context.strokeStyle = .string("#c7cdd6")
        context.lineWidth = .number(1)
        _ = context.strokeRect!(0.5, 0.5, max(0, width - 1), max(0, height - 1))

        guard showLabel, width >= 44, height >= 20 else { return }
        let fontSize = max(8, min(12, height * 0.22))
        context.fillStyle = .string("#657084")
        context.font = .string("650 \(fontSize)px -apple-system, BlinkMacSystemFont, sans-serif")
        context.textAlign = .string("center")
        context.textBaseline = .string("middle")
        _ = context.fillText!(label, width * 0.5, height * 0.5, max(0, width - 12))
    }

    private func layerCount(in items: [DisplayListPreviewItem]) -> Int {
        items.reduce(into: 0) { count, item in
            switch item.value {
            case .empty:
                break
            case let .content(.flattened(_, children)):
                count += layerCount(in: children)
            case .content:
                if item.frame.width > 0, item.frame.height > 0 { count += 1 }
            case let .effect(_, children), let .states(children):
                count += layerCount(in: children)
            }
        }
    }

    private func bounds(
        of items: [DisplayListPreviewItem],
        origin: DisplayListPreviewPoint
    ) -> PreviewBounds? {
        var result: PreviewBounds?
        for item in items {
            let itemOrigin = DisplayListPreviewPoint(
                x: origin.x + item.frame.x,
                y: origin.y + item.frame.y
            )
            let itemBounds: PreviewBounds?
            switch item.value {
            case .empty:
                itemBounds = nil
            case let .content(.flattened(flattenedOrigin, children)):
                itemBounds = bounds(
                    of: children,
                    origin: DisplayListPreviewPoint(
                        x: itemOrigin.x + flattenedOrigin.x,
                        y: itemOrigin.y + flattenedOrigin.y
                    )
                )
            case .content:
                if item.frame.width > 0, item.frame.height > 0 {
                    itemBounds = PreviewBounds(
                        minX: itemOrigin.x,
                        minY: itemOrigin.y,
                        maxX: itemOrigin.x + item.frame.width,
                        maxY: itemOrigin.y + item.frame.height
                    )
                } else {
                    itemBounds = nil
                }
            case let .effect(.transform(transform), children):
                itemBounds = bounds(of: children, origin: .zero)
                    .map { $0.applying(transform).offsetBy(dx: itemOrigin.x, dy: itemOrigin.y) }
            case let .effect(_, children), let .states(children):
                itemBounds = bounds(of: children, origin: itemOrigin)
            }
            if let itemBounds {
                result = result.map { $0.union(itemBounds) } ?? itemBounds
            }
        }
        return result
    }

    private func isFlattened(_ content: DisplayListPreviewContent) -> Bool {
        if case .flattened = content { return true }
        return false
    }
}

private enum PreviewDevice: Equatable {
    case iPhone17Pro
    case iPhone17ProMax
    case iPhoneAir
    case iPhone16e
    case iPhone15Pro
    case window(width: Double, height: Double)

    init(identifier: String, windowWidth: Double, windowHeight: Double) {
        switch identifier {
        case "iphone17promax": self = .iPhone17ProMax
        case "iphoneair": self = .iPhoneAir
        case "iphone16e": self = .iPhone16e
        case "iphone15pro": self = .iPhone15Pro
        case "window":
            self = .window(
                width: Self.sanitized(windowWidth, fallback: 800),
                height: Self.sanitized(windowHeight, fallback: 600)
            )
        default: self = .iPhone17Pro
        }
    }

    var screenBounds: PreviewBounds {
        switch self {
        case .iPhone17Pro:
            PreviewBounds(minX: 0, minY: 0, maxX: 402, maxY: 874)
        case .iPhone17ProMax:
            PreviewBounds(minX: 0, minY: 0, maxX: 440, maxY: 956)
        case .iPhoneAir:
            PreviewBounds(minX: 0, minY: 0, maxX: 420, maxY: 912)
        case .iPhone16e:
            PreviewBounds(minX: 0, minY: 0, maxX: 390, maxY: 844)
        case .iPhone15Pro:
            PreviewBounds(minX: 0, minY: 0, maxX: 393, maxY: 852)
        case let .window(width, height):
            PreviewBounds(minX: 0, minY: 0, maxX: width, maxY: height)
        }
    }

    var stageBounds: PreviewBounds {
        let screen = screenBounds
        if isPhone {
            return PreviewBounds(
                minX: -8,
                minY: -8,
                maxX: screen.maxX + 8,
                maxY: screen.maxY + 8
            )
        }
        return PreviewBounds(
            minX: -8,
            minY: -38,
            maxX: screen.maxX + 8,
            maxY: screen.maxY + 8
        )
    }

    var screenCornerRadius: Double {
        switch self {
        case .iPhone17Pro: 55
        case .iPhone17ProMax: 59
        case .iPhoneAir: 57
        case .iPhone16e: 51
        case .iPhone15Pro: 54
        case .window: 5
        }
    }

    var hasDynamicIsland: Bool {
        switch self {
        case .iPhone16e, .window: false
        default: true
        }
    }

    var isPhone: Bool {
        if case .window = self { return false }
        return true
    }

    private static func sanitized(_ value: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(10_000, max(100, value.rounded()))
    }
}

private struct PreviewBounds {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double

    var width: Double { maxX - minX }
    var height: Double { maxY - minY }

    func union(_ other: PreviewBounds) -> PreviewBounds {
        PreviewBounds(
            minX: min(minX, other.minX),
            minY: min(minY, other.minY),
            maxX: max(maxX, other.maxX),
            maxY: max(maxY, other.maxY)
        )
    }

    func offsetBy(dx: Double, dy: Double) -> PreviewBounds {
        PreviewBounds(minX: minX + dx, minY: minY + dy, maxX: maxX + dx, maxY: maxY + dy)
    }

    func applying(_ transform: DisplayListPreviewTransform) -> PreviewBounds {
        let points = [
            DisplayListPreviewPoint(x: minX, y: minY),
            DisplayListPreviewPoint(x: maxX, y: minY),
            DisplayListPreviewPoint(x: minX, y: maxY),
            DisplayListPreviewPoint(x: maxX, y: maxY),
        ].map { point in
            DisplayListPreviewPoint(
                x: transform.a * point.x + transform.c * point.y + transform.tx,
                y: transform.b * point.x + transform.d * point.y + transform.ty
            )
        }
        return PreviewBounds(
            minX: points.map(\.x).min()!,
            minY: points.map(\.y).min()!,
            maxX: points.map(\.x).max()!,
            maxY: points.map(\.y).max()!
        )
    }
}
