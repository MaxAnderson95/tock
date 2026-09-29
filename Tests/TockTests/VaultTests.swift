import Foundation
import Testing
import TockCore

// Runs against the real login keychain under a throwaway service name, so no test touches the app's own items.
@Test func vaultRoundTripsServicesThroughTheKeychain() throws {
    let vault = Vault(keychainService: "tech.maxanderson.tock.tests.\(UUID().uuidString)")
    defer { for service in (try? vault.load()) ?? [] { try? vault.delete(service.id) } }
    #expect(try vault.load().isEmpty)

    var github = Service(issuer: "GitHub", account: "max", secret: Data("12345678901234567890".utf8))
    let aws = Service(issuer: "aws", secret: Data("abc".utf8), algorithm: .sha512, digits: 8, period: 60)
    try vault.save(github)
    try vault.save(aws)
    #expect(try vault.load() == [aws, github])

    github.account = "max@example.com"
    try vault.save(github)
    #expect(try vault.load() == [aws, github])

    try vault.delete(aws.id)
    #expect(try vault.load() == [github])
}
