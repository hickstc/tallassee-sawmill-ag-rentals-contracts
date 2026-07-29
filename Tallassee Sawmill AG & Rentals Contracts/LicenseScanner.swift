import UIKit
import Vision

// MARK: - Scan result

/// Customer details pulled from a driver license scan.
struct ScannedLicense {
    var fullName = ""
    var address = ""
    var expiration: Date?

    var isEmpty: Bool { fullName.isEmpty && address.isEmpty && expiration == nil }
}

// MARK: - Scanner

/// Reads customer info from a photo of a driver license.
/// Prefers the PDF417 barcode on the back (AAMVA data, very reliable);
/// falls back to recognizing printed text on the front.
enum LicenseScanner {

    static func scan(_ imageData: Data) async -> ScannedLicense? {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        if let payload = await pdf417Payload(cgImage, orientation: orientation),
           let scanned = parseAAMVA(payload), !scanned.isEmpty {
            return scanned
        }
        if let scanned = await recognizeFront(cgImage, orientation: orientation), !scanned.isEmpty {
            return scanned
        }
        return nil
    }

    // MARK: - Barcode (back of license)

    private static func pdf417Payload(_ image: CGImage, orientation: CGImagePropertyOrientation) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectBarcodesRequest()
                request.symbologies = [.pdf417]
                let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
                try? handler.perform([request])
                let payload = request.results?.compactMap { $0.payloadStringValue }.first
                continuation.resume(returning: payload)
            }
        }
    }

    /// Parses the AAMVA element codes out of a PDF417 payload.
    private static func parseAAMVA(_ payload: String) -> ScannedLicense? {
        var fields: [String: String] = [:]
        let cleaned = payload.replacingOccurrences(of: "\r", with: "\n")
        for raw in cleaned.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            // The first element of a subfile is prefixed with the subfile type ("DLDAQ…").
            if line.count > 5, line.hasPrefix("DL") || line.hasPrefix("ID") {
                let rest = String(line.dropFirst(2))
                if rest.hasPrefix("D") { line = rest }
            }
            guard line.count > 3, line.hasPrefix("D") else { continue }
            let code = String(line.prefix(3))
            let value = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if fields[code] == nil, !value.isEmpty { fields[code] = value }
        }

        var result = ScannedLicense()

        // DAC = first name, DCS = last name; DAA = "LAST,FIRST,MIDDLE" on older licenses.
        let first = fields["DAC"] ?? ""
        let last = fields["DCS"] ?? ""
        if !first.isEmpty || !last.isEmpty {
            result.fullName = [first, last].filter { !$0.isEmpty }.joined(separator: " ").capitalized
        } else if let full = fields["DAA"] {
            let parts = full.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            result.fullName = (parts.count >= 2 ? "\(parts[1]) \(parts[0])" : full).capitalized
        }

        // DAG = street, DAI = city, DAJ = state, DAK = zip.
        let street = (fields["DAG"] ?? "").capitalized
        let city = (fields["DAI"] ?? "").capitalized
        let state = (fields["DAJ"] ?? "").uppercased()
        let zip = String((fields["DAK"] ?? "").filter(\.isNumber).prefix(5))
        var addressParts: [String] = []
        if !street.isEmpty { addressParts.append(street) }
        if !city.isEmpty { addressParts.append(city) }
        let stateZip = [state, zip].filter { !$0.isEmpty }.joined(separator: " ")
        if !stateZip.isEmpty { addressParts.append(stateZip) }
        result.address = addressParts.joined(separator: ", ")

        // DBA = expiration date.
        if let dba = fields["DBA"] ?? firstMatch(in: payload, pattern: "DBA(\\d{8})") {
            result.expiration = parseAAMVADate(dba)
        }

        return result.isEmpty ? nil : result
    }

    /// AAMVA dates are 8 digits: MMDDCCYY on current licenses, CCYYMMDD on older ones.
    private static func parseAAMVADate(_ text: String) -> Date? {
        let digits = String(text.filter(\.isNumber).prefix(8))
        guard digits.count == 8 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["MMddyyyy", "yyyyMMdd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: digits) {
                let year = Calendar.current.component(.year, from: date)
                if (1990...2100).contains(year) { return date }
            }
        }
        return nil
    }

    // MARK: - Text recognition (front of license)

    private static func recognizeFront(_ image: CGImage, orientation: CGImagePropertyOrientation) async -> ScannedLicense? {
        let lines: [String] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
                try? handler.perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
        }
        guard !lines.isEmpty else { return nil }

        var result = ScannedLicense()
        let upper = lines.map { $0.uppercased() }

        // Expiration: a date on the same line as (or right after) "EXP".
        for (index, line) in upper.enumerated() where line.contains("EXP") {
            if let date = firstDate(in: line) ?? (index + 1 < upper.count ? firstDate(in: upper[index + 1]) : nil) {
                result.expiration = date
                break
            }
        }

        // Address: a street line ("123 …") followed by a "CITY ST 12345" line.
        var streetIndex: Int?
        for (index, line) in upper.enumerated() {
            if line.range(of: #"^\d+\s+[A-Z0-9 .#-]+$"#, options: .regularExpression) != nil,
               firstDate(in: line) == nil {
                streetIndex = index
                break
            }
        }
        if let streetIndex {
            var parts = [upper[streetIndex].capitalized]
            if streetIndex + 1 < upper.count,
               upper[streetIndex + 1].range(of: #"[A-Z]{2}\s+\d{5}"#, options: .regularExpression) != nil {
                parts.append(formatCityStateZip(upper[streetIndex + 1]))
            }
            result.address = parts.joined(separator: ", ")
        }

        // Name: the first letters-only line with 2+ words that isn't a label or state name.
        // Front layouts vary by state, so this is best-effort; the user can correct it.
        let keywords = ["LICENSE", "DRIVER", "IDENTIFICATION", "USA", "DOB", "EXP", "ISS",
                        "CLASS", "SEX", "HGT", "WGT", "EYES", "HAIR", "REST", "END",
                        "DUPS", "ORGAN", "DONOR", "VETERAN", "ALABAMA", "GEORGIA",
                        "FLORIDA", "TENNESSEE", "MISSISSIPPI"]
        for line in upper {
            guard line.count >= 4,
                  line.range(of: #"^[A-Z ,'-]+$"#, options: .regularExpression) != nil,
                  !keywords.contains(where: { line.contains($0) }),
                  line.split(separator: " ").count >= 2
            else { continue }
            result.fullName = line.capitalized
            break
        }

        return result.isEmpty ? nil : result
    }

    // MARK: - Helpers

    private static func formatCityStateZip(_ line: String) -> String {
        line.split(separator: " ").map { word in
            let w = String(word)
            if w.range(of: #"^[A-Z]{2}$"#, options: .regularExpression) != nil { return w }
            if w.allSatisfy(\.isNumber) { return w }
            return w.capitalized
        }.joined(separator: " ")
    }

    private static func firstDate(in text: String) -> Date? {
        guard let range = text.range(of: #"\d{1,2}[/-]\d{1,2}[/-]\d{2,4}"#, options: .regularExpression) else { return nil }
        let raw = String(text[range]).replacingOccurrences(of: "-", with: "/")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["MM/dd/yyyy", "MM/dd/yy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
