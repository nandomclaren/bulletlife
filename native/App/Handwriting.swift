// Handwriting recognition on the device (phase N3): Google ML Kit Digital Ink, offline once its model for the
// language (~20 MB) is downloaded. This file doesn't import BulletLifeCore, whose Stroke and Ink would clash
// with ML Kit's: it reads plain point lists. Without the ML Kit pod (before `pod install`) the app builds and
// runs, and transcription just waits.
import Foundation
import SwiftUI

#if canImport(MLKit)
    import MLKit
#endif

/// Handwriting languages (Settings › Handwriting), as ML Kit's language tags.
enum HandwritingLang: String, CaseIterable, Identifiable {
    case ptBR = "pt-BR"
    case enUS = "en-US"
    var id: String { rawValue }
    var name: String { self == .ptBR ? S.portugueseBR : S.englishUS }
}

@MainActor
final class Handwriting: ObservableObject {
    static let shared = Handwriting()

    enum Status: Equatable {
        /// Built without the ML Kit pod.
        case unavailable
        case notDownloaded
        case downloading
        case ready
        case failed
    }

    @Published private(set) var status: Status = .unavailable

    #if canImport(MLKit)
        private var lang: HandwritingLang?
        private var model: DigitalInkRecognitionModel?
        private var recognizer: DigitalInkRecognizer?
        private var observers: [NSObjectProtocol] = []

        private init() {
            status = .notDownloaded
            for name in [NSNotification.Name.mlkitModelDownloadDidSucceed, .mlkitModelDownloadDidFail] {
                observers.append(
                    NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                        let failed = note.name == .mlkitModelDownloadDidFail
                        Task { @MainActor in self?.downloadEnded(failed: failed) }
                    })
            }
        }

        /// Chooses the language's model and starts its download if it isn't on the device yet.
        func prepare(_ lang: HandwritingLang) {
            if self.lang != lang {
                self.lang = lang
                recognizer = nil
                model = DigitalInkRecognitionModelIdentifier(forLanguageTag: lang.rawValue).map { DigitalInkRecognitionModel(modelIdentifier: $0) }
            }
            guard let model else { return status = .failed }
            if ModelManager.modelManager().isModelDownloaded(model) {
                status = .ready
            } else if status != .downloading {
                status = .downloading
                _ = ModelManager.modelManager().download(
                    model, conditions: ModelDownloadConditions(allowsCellularAccess: true, allowsBackgroundDownloading: true))
            }
        }

        private func downloadEnded(failed: Bool) {
            guard let model else { return }
            status = ModelManager.modelManager().isModelDownloaded(model) ? .ready : failed ? .failed : status
        }

        /// The text of these strokes (flat [x, y, pressure, ...] each, in writing order), or nil when the
        /// recognizer can't read now (model not downloaded yet, or an error): the line waits for the next pass.
        func recognize(_ strokes: [[Double]], lang: HandwritingLang) async -> String? {
            prepare(lang)
            guard status == .ready, let model else { return nil }
            if strokes.isEmpty { return "" }
            if recognizer == nil {
                recognizer = DigitalInkRecognizer.digitalInkRecognizer(options: DigitalInkRecognizerOptions(model: model))
            }
            guard let recognizer else { return nil }
            // Stored strokes have no times: points get evenly spaced ones, in writing order, as the PWA sends them.
            var t = 0
            let ink = Ink(
                strokes: strokes.map { p in
                    var points: [StrokePoint] = []
                    var i = 0
                    while i + 1 < p.count {
                        t += 8
                        points.append(StrokePoint(x: Float(p[i]), y: Float(p[i + 1]), t: t))
                        i += 3
                    }
                    t += 120
                    return Stroke(points: points)
                })
            return await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
                recognizer.recognize(ink: ink) { result, _ in
                    let text = result?.candidates.first?.text
                    done.resume(returning: text.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") })
                }
            }
        }
    #else
        private init() {}
        func prepare(_ lang: HandwritingLang) {}
        func recognize(_ strokes: [[Double]], lang: HandwritingLang) async -> String? { nil }
    #endif
}
