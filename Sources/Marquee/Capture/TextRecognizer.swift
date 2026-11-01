import Foundation
import Vision

/// What Copy Text found in an image: printed text, and the contents of any QR codes or
/// barcodes.
struct RecognizedContent: Equatable {
    var text: String
    /// Decoded QR code and barcode contents, in the order Vision reports them.
    var codes: [String]

    var isEmpty: Bool { text.isEmpty && codes.isEmpty }

    /// What goes on the clipboard: the codes first (scanning one is usually the point), then the
    /// text, each once.
    var clipboardText: String {
        var parts: [String] = []
        for part in codes + [text] where !part.isEmpty && !parts.contains(part) {
            parts.append(part)
        }
        return parts.joined(separator: "\n\n")
    }

    /// Links to offer, codes first.
    var links: [URL] { LinkFinder.links(in: clipboardText) }

    /// "Copied QR code", "Copied text (120 characters)", "Copied text and QR code"…
    var summary: String {
        let code = codes.count == 1 ? "QR code" : "\(codes.count) codes"
        switch (text.isEmpty, codes.isEmpty) {
        case (false, true): return "Copied text (\(text.count) characters)"
        case (true, false): return "Copied \(code)"
        case (false, false): return "Copied text and \(code)"
        case (true, true): return "No text or QR code found"
        }
    }
}

/// On-device text and QR code recognition with Apple's Vision framework (the engine behind
/// Live Text).
enum TextRecognizer {
    static func recognize(imageAt url: URL, completion: @escaping @MainActor (RecognizedContent) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true
            textRequest.automaticallyDetectsLanguage = true
            // QR codes, plus the other symbologies Vision reads (Aztec, Data Matrix, PDF417, EAN…).
            let codeRequest = VNDetectBarcodesRequest()

            let handler = VNImageRequestHandler(url: url, options: [:])
            var content = RecognizedContent(text: "", codes: [])
            do {
                try handler.perform([textRequest, codeRequest])
                content.text = (textRequest.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                var codes: [String] = []
                for payload in (codeRequest.results ?? []).compactMap(\.payloadStringValue)
                where !payload.isEmpty && !codes.contains(payload) {
                    codes.append(payload)
                }
                content.codes = codes
            } catch {
                NSLog("Marquee: text recognition failed: \(error)")
            }
            Task { @MainActor in completion(content) }
        }
    }
}
