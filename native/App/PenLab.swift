// Pen lab (prototype, iPad): a stroke of our own on top of PencilKit. PencilKit keeps receiving the Pencil (its
// ink is made invisible; "Show PencilKit's ink" turns it on to compare), a passive recognizer reads the same
// touches with their coalesced and predicted samples, and `PenBrush` (BulletLifeCore) turns them into the shape we
// draw, with a pressure curve we can tune. Nothing here touches the pen page: it is a place to feel the line and
// choose the numbers before the pen page uses them.
#if os(iOS) && !targetEnvironment(macCatalyst)
    import BulletLifeCore
    import PencilKit
    import SwiftUI
    import UIKit
    import UIKit.UIGestureRecognizerSubclass

    struct PenLabView: View {
        @State private var params = PenLabView.saved()
        @State private var showPencilKit = false
        @State private var clears = 0
        @State private var force = 0.0
        @State private var counts = "Touches heard: none yet"
        @State private var frames = FrameWatch()

        var body: some View {
            ZStack(alignment: .bottom) {
                PenLabCanvas(params: params, showPencilKit: showPencilKit, clears: clears, onForce: { force = $0 }, onCounts: { counts = $0 })
                    .background(Color(uiColor: Theme.ui("bg")))
                    .ignoresSafeArea(edges: .bottom)
                controls
            }
            .navigationTitle("Pen lab")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: params) { Self.save(params) }
            .onAppear { frames.start() }
            .onDisappear { frames.stop() }
        }

        private var controls: some View {
            VStack(spacing: 6) {
                HStack {
                    ForEach(Self.presets, id: \.0) { name, p in
                        Button(name) { params = p }.buttonStyle(.bordered)
                    }
                    Spacer()
                    Toggle("PencilKit's ink", isOn: $showPencilKit).fixedSize()
                    Button("Clear") { clears += 1 }.buttonStyle(.bordered)
                }
                slider("Pressure curve", $params.gamma, 0.3...3, "\(String(format: "%.2f", params.gamma))  (below 1: swells with a light touch)")
                slider("Thin width", $params.minWidth, 0.3...4, String(format: "%.1f pt at zero pressure", params.minWidth))
                slider("Full width", $params.maxWidth, 1...9, String(format: "%.1f pt at full pressure", params.maxWidth))
                slider("Smoothing", $params.smoothing, 0...0.95, String(format: "%.2f", params.smoothing))
                slider("Soft ends", $params.taper, 0...24, String(format: "%.0f pt", params.taper))
                slider("Thin when fast", $params.velocityThinning, 0...0.8, String(format: "%.2f", params.velocityThinning))
                Text(String(format: "Pressure now: %.2f  ·  ", force) + counts).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(12)
        }

        private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ readout: String) -> some View {
            HStack {
                Text(title).frame(width: 130, alignment: .leading)
                Slider(value: value, in: range)
                Text(readout).font(.footnote.monospacedDigit()).foregroundStyle(.secondary).frame(width: 260, alignment: .leading)
            }
        }

        static let presets: [(String, BrushParams)] = [
            ("Flat (today)", .flat),
            ("Soft", BrushParams()),
            ("Firm", BrushParams(minWidth: 0.6, maxWidth: 4, gamma: 1.6, smoothing: 0.5, taper: 4, velocityThinning: 0.1)),
            ("Ink", BrushParams(minWidth: 0.5, maxWidth: 5, gamma: 0.6, smoothing: 0.7, taper: 12, velocityThinning: 0.3)),
        ]

        private static func saved() -> BrushParams {
            UserDefaults.standard.data(forKey: "penLabParams").flatMap { try? JSONDecoder().decode(BrushParams.self, from: $0) } ?? BrushParams()
        }

        private static func save(_ p: BrushParams) {
            if let data = try? JSONEncoder().encode(p) { UserDefaults.standard.set(data, forKey: "penLabParams") }
        }
    }

    /// Where the Pencil's samples come from. Two readers are tried at once (a canvas subclass and a passive
    /// recognizer); whichever hears a stroke first owns it, and the counters say which one works.
    final class LabInput {
        var ink: LabInkView?
        var onForce: (Double) -> Void = { _ in }
        var onCounts: (String) -> Void = { _ in }
        private var owner: Int?
        private var counts = [0, 0]
        private var samples = 0

        private func report() {
            onCounts("Touches heard: canvas \(counts[0]), recognizer \(counts[1]); samples \(samples)")
        }

        func began(_ source: Int, _ t: UITouch, in view: UIView) {
            guard owner == nil else { return }
            owner = source
            counts[source] += 1
            let p = Self.sample(t, in: view)
            ink?.begin(p)
            onForce(p.force)
            report()
        }

        func moved(_ source: Int, _ t: UITouch, _ event: UIEvent?, in view: UIView) {
            guard owner == source else { return }
            let real = (event?.coalescedTouches(for: t) ?? [t]).map { Self.sample($0, in: view) }
            let guess = (event?.predictedTouches(for: t) ?? []).map { Self.sample($0, in: view) }
            samples += real.count
            ink?.extend(real, predicted: guess)
            if let last = real.last { onForce(last.force) }
            report()
        }

        func ended(_ source: Int, keep: Bool) {
            guard owner == source else { return }
            owner = nil
            // PencilKit may cancel a touch it took over: what was written until then is kept.
            ink?.end(keep: true)
        }

        static func sample(_ t: UITouch, in view: UIView) -> BrushPoint {
            let at = t.location(in: view)
            return BrushPoint(x: at.x, y: at.y, force: t.maximumPossibleForce > 0 ? Double(t.force / t.maximumPossibleForce) : 0)
        }
    }

    /// The canvas hears the Pencil's touches too (it passes everything on to PencilKit).
    final class LabCanvas: PKCanvasView {
        var input: LabInput?
        var inkView: UIView?

        private func pencil(_ touches: Set<UITouch>) -> UITouch? { touches.first { $0.type == .pencil } }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesBegan(touches, with: event)
            if let t = pencil(touches), let v = inkView { input?.began(0, t, in: v) }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesMoved(touches, with: event)
            if let t = pencil(touches), let v = inkView { input?.moved(0, t, event, in: v) }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesEnded(touches, with: event)
            if pencil(touches) != nil { input?.ended(0, keep: true) }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            super.touchesCancelled(touches, with: event)
            if pencil(touches) != nil { input?.ended(0, keep: false) }
        }
    }

    /// Reads the Pencil's touches without taking them from PencilKit (it never leaves the possible state).
    final class TouchObserver: UIGestureRecognizer {
        var began: ((UITouch) -> Void)?
        var moved: ((UITouch, UIEvent) -> Void)?
        var ended: ((UITouch, Bool) -> Void)?

        override init(target: Any?, action: Selector?) {
            super.init(target: target, action: action)
            allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
            cancelsTouchesInView = false
            delaysTouchesBegan = false
            delaysTouchesEnded = false
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { touches.forEach { began?($0) } }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) { touches.forEach { moved?($0, event) } }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { touches.forEach { ended?($0, true) } }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { touches.forEach { ended?($0, false) } }
    }

    /// Draws the strokes: finished ones in one layer, the one being written in another (rebuilt on each touch event).
    final class LabInkView: UIView {
        var params = BrushParams() { didSet { if params != oldValue { redrawAll() } } }
        private(set) var strokes: [[BrushPoint]] = []
        private var live: [BrushPoint] = []
        private var predicted: [BrushPoint] = []
        private let done = CAShapeLayer()
        private let current = CAShapeLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isOpaque = false
            for l in [done, current] {
                layer.addSublayer(l)
                l.actions = ["path": NSNull()]
            }
            paintColor()
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        /// The ink is the text color of the current appearance (black on a light page, white on a dark one).
        private func paintColor() {
            let c = traitCollection.userInterfaceStyle == .dark ? UIColor.white : UIColor.black
            for l in [done, current] { l.fillColor = c.cgColor }
        }

        override func traitCollectionDidChange(_ previous: UITraitCollection?) {
            super.traitCollectionDidChange(previous)
            paintColor()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            paintColor()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            done.frame = bounds
            current.frame = bounds
        }

        func begin(_ p: BrushPoint) {
            live = [p]
            predicted = []
            drawLive()
        }

        func extend(_ real: [BrushPoint], predicted guess: [BrushPoint]) {
            live += real
            predicted = guess
            drawLive()
        }

        func end(keep: Bool) {
            if keep, !live.isEmpty { strokes.append(live) }
            live = []
            predicted = []
            current.path = nil
            redrawAll()
        }

        func clear() {
            strokes = []
            live = []
            predicted = []
            current.path = nil
            done.path = nil
        }

        private func drawLive() {
            current.path = Self.path(live + predicted, params)
        }

        private func redrawAll() {
            let all = CGMutablePath()
            for s in strokes { all.addPath(Self.path(s, params)) }
            done.path = all
        }

        static func path(_ points: [BrushPoint], _ params: BrushParams) -> CGPath {
            let o = PenBrush.outline(points, params)
            let path = CGMutablePath()
            guard o.count >= 6 else { return path }
            path.move(to: CGPoint(x: o[0], y: o[1]))
            var i = 2
            while i + 1 < o.count {
                path.addLine(to: CGPoint(x: o[i], y: o[i + 1]))
                i += 2
            }
            path.closeSubpath()
            return path
        }
    }

    struct PenLabCanvas: UIViewRepresentable {
        var params: BrushParams
        var showPencilKit: Bool
        var clears: Int
        var onForce: (Double) -> Void
        var onCounts: (String) -> Void

        final class Coordinator {
            var clears = 0
            weak var canvas: PKCanvasView?
            weak var ink: LabInkView?
            let input = LabInput()
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeUIView(context: Context) -> UIView {
            let root = UIView()
            let canvas = LabCanvas()
            canvas.drawingPolicy = .pencilOnly
            canvas.backgroundColor = .clear
            canvas.isScrollEnabled = false
            canvas.frame = root.bounds
            canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            let ink = LabInkView()
            ink.frame = root.bounds
            ink.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            root.addSubview(canvas)
            root.addSubview(ink)
            let input = context.coordinator.input
            input.ink = ink
            input.onForce = onForce
            input.onCounts = onCounts
            canvas.input = input
            canvas.inkView = ink
            let observer = TouchObserver(target: nil, action: nil)
            observer.began = { t in input.began(1, t, in: ink) }
            observer.moved = { t, event in input.moved(1, t, event, in: ink) }
            observer.ended = { _, kept in input.ended(1, keep: kept) }
            canvas.addGestureRecognizer(observer)
            context.coordinator.canvas = canvas
            context.coordinator.ink = ink
            return root
        }

        func updateUIView(_ root: UIView, context: Context) {
            guard let canvas = context.coordinator.canvas, let ink = context.coordinator.ink else { return }
            ink.params = params
            // PencilKit's own line stays out of sight (it only receives the Pencil), or shows in red to compare.
            canvas.tool = PKInkingTool(.pen, color: showPencilKit ? UIColor.systemRed.withAlphaComponent(0.6) : .clear, width: 3)
            if clears != context.coordinator.clears {
                context.coordinator.clears = clears
                ink.clear()
                canvas.drawing = PKDrawing()
            }
        }
    }
#endif
