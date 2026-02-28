import Foundation
import AuthenticationServices
import CryptoKit
import Security

/// Handles Spotify OAuth PKCE flow via ASWebAuthenticationSession.
/// User must create a Spotify Developer App and set clientId below.
struct SpotifyAuth {
    static let redirectURI = "crates://spotify-callback"
    static let scopes = "user-read-currently-playing user-read-playback-state"

    // MARK: - PKCE helpers

    static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    static func codeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncoded()
    }

    static func buildAuthURL(clientId: String, verifier: String) -> URL? {
        let challenge = codeChallenge(for: verifier)
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            .init(name: "response_type",    value: "code"),
            .init(name: "client_id",        value: clientId),
            .init(name: "redirect_uri",     value: redirectURI),
            .init(name: "scope",            value: scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge",   value: challenge),
            .init(name: "show_dialog",      value: "false"),
        ]
        return components?.url
    }

    // MARK: - Token exchange

    struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
        let token_type: String
    }

    static func exchangeCode(
        _ code: String,
        clientId: String,
        verifier: String
    ) async throws -> TokenResponse {
        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type":    "authorization_code",
            "code":          code,
            "redirect_uri":  redirectURI,
            "client_id":     clientId,
            "code_verifier": verifier,
        ]
        request.httpBody = body.formEncoded()
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    static func refreshToken(
        _ refreshToken: String,
        clientId: String
    ) async throws -> TokenResponse {
        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type":    "refresh_token",
            "refresh_token": refreshToken,
            "client_id":     clientId,
        ]
        request.httpBody = body.formEncoded()
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - Keychain helpers

    private static let accessKey  = "SpotifyAccessToken"
    private static let refreshKey = "SpotifyRefreshToken"
    private static let expiryKey  = "SpotifyTokenExpiry"
    private static let clientKey  = "SpotifyClientId"
    private static let service    = "com.djmunya.crates"

    static func saveTokens(
        access: String,
        refresh: String?,
        expiresIn: Int,
        clientId: String
    ) {
        save(key: accessKey,  value: access)
        save(key: clientKey,  value: clientId)
        if let refresh { save(key: refreshKey, value: refresh) }
        let expiry = Date().addingTimeInterval(Double(expiresIn - 60))
        save(key: expiryKey, value: ISO8601DateFormatter().string(from: expiry))
    }

    static func loadAccessToken() -> String?  { load(key: accessKey) }
    static func loadRefreshToken() -> String? { load(key: refreshKey) }
    static func loadClientId() -> String?     { load(key: clientKey) }

    static func loadTokenExpiry() -> Date? {
        guard let str = load(key: expiryKey) else { return nil }
        return ISO8601DateFormatter().date(from: str)
    }

    static func clearTokens() {
        [accessKey, refreshKey, expiryKey].forEach(delete)
    }

    private static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      key,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      key,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Data extensions

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension Dictionary where Key == String, Value == String {
    func formEncoded() -> Data {
        map { k, v in
            "\(k.urlEncoded())=\(v.urlEncoded())"
        }
        .joined(separator: "&")
        .data(using: .utf8) ?? Data()
    }
}

extension String {
    func urlEncoded() -> String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
