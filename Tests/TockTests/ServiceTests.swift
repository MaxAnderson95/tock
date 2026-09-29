import Foundation
import Testing
import TockCore

// RFC 6238 Appendix B. Each algorithm uses the ASCII seed repeated to its HMAC block-friendly key length.
private let seed1 = Data("12345678901234567890".utf8)
private let seed256 = Data("12345678901234567890123456789012".utf8)
private let seed512 = Data("1234567890123456789012345678901234567890123456789012345678901234".utf8)

@Test(arguments: [
    (59.0, "94287082", "46119246", "90693936"),
    (1111111109, "07081804", "68084774", "25091201"),
    (1111111111, "14050471", "67062674", "99943326"),
    (1234567890, "89005924", "91819424", "93441116"),
    (2000000000, "69279037", "90698825", "38618901"),
    (20000000000, "65353130", "77737706", "47863826"),
])
func rfc6238Vectors(time: Double, sha1: String, sha256: String, sha512: String) {
    let date = Date(timeIntervalSince1970: time)
    #expect(Service(issuer: "RFC", secret: seed1, algorithm: .sha1, digits: 8).code(at: date) == sha1)
    #expect(Service(issuer: "RFC", secret: seed256, algorithm: .sha256, digits: 8).code(at: date) == sha256)
    #expect(Service(issuer: "RFC", secret: seed512, algorithm: .sha512, digits: 8).code(at: date) == sha512)
}

@Test func defaultsAreSixDigitsThirtySecondsSHA1() {
    let service = Service(issuer: "RFC", secret: seed1)
    #expect(service.digits == 6 && service.period == 30 && service.algorithm == .sha1)
    #expect(service.code(at: Date(timeIntervalSince1970: 59)) == "287082")
}

@Test func periodChangesTheTimeStep() {
    let service = Service(issuer: "RFC", secret: seed1, digits: 8, period: 60)
    // With a 60 second step, t=59 falls in counter 0, which RFC 30 second vectors reach at t=0..29.
    #expect(service.code(at: Date(timeIntervalSince1970: 59)) == Service(issuer: "RFC", secret: seed1, digits: 8).code(at: Date(timeIntervalSince1970: 10)))
    #expect(service.remaining(at: Date(timeIntervalSince1970: 59)) == 1)
    #expect(service.remaining(at: Date(timeIntervalSince1970: 60)) == 60)
}

@Test func base32AcceptsHowSitesPrintKeys() {
    #expect(Base32.decode("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ") == seed1)
    #expect(Base32.decode("gezd gnbv gy3t qojq gezd gnbv gy3t qojq") == seed1)
    #expect(Base32.decode("GEZDGNBV-GY3TQOJQ-GEZDGNBV-GY3TQOJQ") == seed1)
    #expect(Base32.decode("MZXW6===") == Data("foo".utf8))
    #expect(Base32.decode("not base32!") == nil)
    #expect(Base32.decode("   ") == nil)
    #expect(Base32.encode(seed1) == "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
    #expect(Base32.encode(Data("foo".utf8)) == "MZXW6")
}

@Test func otpauthLinkFillsEveryField() throws {
    let service = try Service(otpauth: "otpauth://totp/ACME%20Co:john@example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=ACME%20Co&algorithm=SHA256&digits=8&period=60")
    #expect(service.issuer == "ACME Co")
    #expect(service.account == "john@example.com")
    #expect(service.secret == seed1)
    #expect(service.algorithm == .sha256 && service.digits == 8 && service.period == 60)
}

@Test func otpauthLinkWithEncodedColonAndBackslashInLabel() throws {
    let service = try Service(otpauth: "otpauth://totp/NetworkSecurity%3AGFCU02%5C_manderson?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=NetworkSecurity&algorithm=SHA1&digits=6&period=30")
    #expect(service.issuer == "NetworkSecurity")
    #expect(service.account == "GFCU02\\_manderson")
    #expect(service.secret == seed1 && service.algorithm == .sha1 && service.digits == 6 && service.period == 30)
}

@Test func otpauthLinkDefaultsAndLabelFallbacks() throws {
    let bare = try Service(otpauth: "otpauth://totp/GitHub:max?secret=GEZDGNBVGY3TQOJQ")
    #expect(bare.issuer == "GitHub" && bare.account == "max")
    #expect(bare.algorithm == .sha1 && bare.digits == 6 && bare.period == 30)
    let accountOnly = try Service(otpauth: "otpauth://totp/max@example.com?secret=GEZDGNBVGY3TQOJQ")
    #expect(accountOnly.issuer == "max@example.com" && accountOnly.account == "")
}

@Test func otpauthLinkRejectsWhatTockCannotGenerate() {
    #expect(throws: Service.ParseError.notTOTP) { try Service(otpauth: "otpauth://hotp/X?secret=GEZDGNBV&counter=1") }
    #expect(throws: Service.ParseError.missingSecret) { try Service(otpauth: "otpauth://totp/X") }
    #expect(throws: Service.ParseError.invalidSecret) { try Service(otpauth: "otpauth://totp/X?secret=1111") }
    #expect(throws: Service.ParseError.invalidDigits) { try Service(otpauth: "otpauth://totp/X?secret=GEZDGNBV&digits=9") }
    #expect(throws: Service.ParseError.invalidAlgorithm) { try Service(otpauth: "otpauth://totp/X?secret=GEZDGNBV&algorithm=MD5") }
}
