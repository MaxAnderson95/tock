import CryptoKit
import Foundation

public enum Algorithm: String, Codable, CaseIterable, Sendable {
    case sha1 = "SHA1", sha256 = "SHA256", sha512 = "SHA512"

    public var label: String {
        switch self {
        case .sha1: "SHA-1"
        case .sha256: "SHA-256"
        case .sha512: "SHA-512"
        }
    }
}

/// One site or app that Tock generates time-based codes for (RFC 6238).
public struct Service: Codable, Identifiable, Hashable, Sendable {
    public static let digitChoices = [6, 7, 8]
    public static let periodRange = 5...300

    public var id: UUID
    public var issuer: String
    public var account: String
    public var secret: Data
    public var algorithm: Algorithm
    public var digits: Int
    public var period: Int

    public init(id: UUID = UUID(), issuer: String, account: String = "", secret: Data,
                algorithm: Algorithm = .sha1, digits: Int = 6, period: Int = 30) {
        self.id = id
        self.issuer = issuer
        self.account = account
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
    }

    public func code(at date: Date) -> String {
        var counter = UInt64(floor(date.timeIntervalSince1970 / Double(period))).bigEndian
        let message = Data(bytes: &counter, count: 8)
        let key = SymmetricKey(data: secret)
        let mac: Data = switch algorithm {
        case .sha1: Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256: Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512: Data(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
        // RFC 4226 section 5.3 dynamic truncation.
        let offset = Int(mac[mac.count - 1] & 0x0f)
        let binary = mac[offset..<offset + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) } & 0x7fff_ffff
        let value = UInt64(binary) % pow10(digits)
        let text = String(value)
        return String(repeating: "0", count: digits - text.count) + text
    }

    /// Seconds until the code shown at `date` expires, in (0, period].
    public func remaining(at date: Date) -> TimeInterval {
        let period = Double(period)
        return period - date.timeIntervalSince1970.truncatingRemainder(dividingBy: period)
    }

    private func pow10(_ n: Int) -> UInt64 { (0..<n).reduce(1) { value, _ in value * 10 } }
}

extension Service {
    public enum ParseError: Error, Equatable, LocalizedError {
        case notTOTP, missingSecret, invalidSecret, invalidDigits, invalidPeriod, invalidAlgorithm

        public var errorDescription: String? {
            switch self {
            case .notTOTP: "Only otpauth://totp links are supported."
            case .missingSecret: "The link has no secret."
            case .invalidSecret: "The secret is not valid Base32."
            case .invalidDigits: "Digits must be 6, 7, or 8."
            case .invalidPeriod: "The period must be between \(Service.periodRange.lowerBound) and \(Service.periodRange.upperBound) seconds."
            case .invalidAlgorithm: "The algorithm must be SHA1, SHA256, or SHA512."
            }
        }
    }

    /// Reads a Key URI (`otpauth://totp/Issuer:account?secret=...`), the format behind setup QR codes.
    public init(otpauth link: String) throws(ParseError) {
        guard let components = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "otpauth", components.host?.lowercased() == "totp" else { throw .notTOTP }
        let query = Dictionary((components.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        guard let encoded = query["secret"], !encoded.isEmpty else { throw .missingSecret }
        guard let secret = Base32.decode(encoded) else { throw .invalidSecret }

        let label = String(components.path.drop { $0 == "/" })
        let parts = label.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let issuer = query["issuer"].flatMap { $0.isEmpty ? nil : $0 } ?? (parts.count == 2 ? parts[0] : "")
        let account = parts.last ?? ""

        var algorithm = Algorithm.sha1
        if let name = query["algorithm"] {
            guard let parsed = Algorithm(rawValue: name.uppercased()) else { throw .invalidAlgorithm }
            algorithm = parsed
        }
        var digits = 6
        if let text = query["digits"] {
            guard let value = Int(text), Service.digitChoices.contains(value) else { throw .invalidDigits }
            digits = value
        }
        var period = 30
        if let text = query["period"] {
            guard let value = Int(text), Service.periodRange.contains(value) else { throw .invalidPeriod }
            period = value
        }
        self.init(issuer: issuer.isEmpty ? account : issuer, account: issuer.isEmpty ? "" : account,
                  secret: secret, algorithm: algorithm, digits: digits, period: period)
    }
}
