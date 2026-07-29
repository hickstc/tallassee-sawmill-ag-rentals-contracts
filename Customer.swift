import Foundation

/// Maps a parsed CSV header→value row into the app's `Customer` model (name, phone, email, address).
/// Header names are matched flexibly (case-insensitive, punctuation-insensitive) and address parts are joined.
struct CustomerFactory {
    static func fromCSVRow(_ row: [String: String]) -> Customer? {
        // Build a normalized lookup of header→value
        var map: [String: String] = [:]
        for (k, v) in row {
            map[normalize(k)] = v.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Name is required; accept common variants
        let name = firstValue(in: map, keys: [
            "customer full name", "full name", "display name", "customer name", "customer", "name", "company", "customer/name"
        ])
        guard let name, !name.isEmpty else { return nil }

        // Phone/email are optional
        let phone = firstValue(in: map, keys: ["phone", "mobile", "cell", "phone number"]) ?? ""
        let email = firstValue(in: map, keys: ["email", "e-mail"]) ?? ""

        // Address: combine any available parts (street, city, state, zip, country)
        var addressParts: [String] = []
        if let street = firstValue(in: map, keys: ["billing address", "bill address", "address", "street address", "street"]) { addressParts.append(cleanAddress(street)) }
        if let city = firstValue(in: map, keys: ["billing city", "bill city", "city"]) { addressParts.append(city) }
        if let state = firstValue(in: map, keys: ["billing state", "bill state", "state", "province"]) { addressParts.append(state) }
        if let zip = firstValue(in: map, keys: ["billing zip", "bill zip", "zip", "postal", "postal code", "postcode"]) { addressParts.append(zip) }
        if let country = firstValue(in: map, keys: ["country"]) { addressParts.append(country) }
        let address = addressParts
            .map { $0.replacingOccurrences(of: "\n", with: ", ").replacingOccurrences(of: "  ", with: " ") }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: ", ")

        var customer = Customer()
        customer.name = name
        customer.phone = cleanPhone(phone)
        customer.email = email
        customer.address = address
        return customer
    }

    // MARK: - Helpers

    private static func normalize(_ s: String) -> String {
        let lowered = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(filtered))
    }

    private static func firstValue(in map: [String: String], keys: [String]) -> String? {
        for key in keys {
            let nk = normalize(key)
            if let v = map[nk], !v.isEmpty { return v }
        }
        // fallback: substring match
        for (k, v) in map where !v.isEmpty {
            if keys.contains(where: { normalize($0).contains(k) || k.contains(normalize($0)) }) { return v }
        }
        return nil
    }

    /// QuickBooks exports multi-line addresses inside one quoted cell; flatten to one line.
    private static func cleanAddress(_ s: String) -> String {
        s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Strips "Phone:"/"Mobile:" prefixes QuickBooks sometimes includes.
    private static func cleanPhone(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["phone:", "mobile:", "cell:"] where t.lowercased().hasPrefix(prefix) {
            t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return t
    }
}
