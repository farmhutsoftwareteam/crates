import Foundation
import SwiftUI
import AuthenticationServices
import Combine

struct SpotifyTrack: Equatable {
    let id: String
    let title: String
    let artist: String
    let bpm: Int?
    let key: String?
    let durationMs: Int
    let albumArtURL: String?
    let isPlaying: Bool
}

class SpotifyState: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published var currentTrack: SpotifyTrack?
    @Published var isAuthenticated = false
    @Published var isConnecting = false
    @Published var clientId: String = ""

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    private var pollTask: Task<Void, Never>?
    private var pendingVerifier: String?

    override init() {
        super.init()
        clientId = SpotifyAuth.loadClientId() ?? ""
        if let token = SpotifyAuth.loadAccessToken() {
            accessToken = token
            refreshToken = SpotifyAuth.loadRefreshToken()
            tokenExpiry = SpotifyAuth.loadTokenExpiry()
            isAuthenticated = true
            startPolling()
        }
    }

    // MARK: - Auth

    func connect() {
        guard !clientId.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let verifier = SpotifyAuth.generateCodeVerifier()
        pendingVerifier = verifier
        guard let authURL = SpotifyAuth.buildAuthURL(clientId: clientId, verifier: verifier) else { return }

        isConnecting = true
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "crates"
        ) { [weak self] callbackURL, error in
            DispatchQueue.main.async {
                self?.isConnecting = false
                if let url = callbackURL {
                    self?.handleCallback(url: url)
                }
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    func handleCallback(url: URL) {
        guard url.scheme == "crates",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let verifier = pendingVerifier else { return }
        pendingVerifier = nil

        Task {
            do {
                let tokens = try await SpotifyAuth.exchangeCode(
                    code,
                    clientId: clientId,
                    verifier: verifier
                )
                await MainActor.run {
                    SpotifyAuth.saveTokens(
                        access: tokens.access_token,
                        refresh: tokens.refresh_token,
                        expiresIn: tokens.expires_in,
                        clientId: clientId
                    )
                    self.accessToken = tokens.access_token
                    self.refreshToken = tokens.refresh_token
                    self.tokenExpiry = Date().addingTimeInterval(Double(tokens.expires_in - 60))
                    self.isAuthenticated = true
                    self.startPolling()
                }
            } catch {
                print("Spotify auth error: \(error)")
            }
        }
    }

    func disconnect() {
        stopPolling()
        SpotifyAuth.clearTokens()
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        isAuthenticated = false
        currentTrack = nil
    }

    // MARK: - Token refresh

    private func validAccessToken() async -> String? {
        if let expiry = tokenExpiry, Date() < expiry, let token = accessToken {
            return token
        }
        guard let refresh = refreshToken else { return nil }
        do {
            let tokens = try await SpotifyAuth.refreshToken(refresh, clientId: clientId)
            await MainActor.run {
                SpotifyAuth.saveTokens(
                    access: tokens.access_token,
                    refresh: tokens.refresh_token ?? refresh,
                    expiresIn: tokens.expires_in,
                    clientId: clientId
                )
                self.accessToken = tokens.access_token
                if let newRefresh = tokens.refresh_token { self.refreshToken = newRefresh }
                self.tokenExpiry = Date().addingTimeInterval(Double(tokens.expires_in - 60))
            }
            return tokens.access_token
        } catch {
            await MainActor.run { self.isAuthenticated = false }
            return nil
        }
    }

    // MARK: - Polling

    private func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetchCurrentlyPlaying()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func fetchCurrentlyPlaying() async {
        guard let token = await validAccessToken() else { return }
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse else { return }

        if httpResponse.statusCode == 204 {
            // Nothing playing
            await MainActor.run { self.currentTrack = nil }
            return
        }
        guard httpResponse.statusCode == 200 else { return }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let isPlaying = json["is_playing"] as? Bool,
              let item = json["item"] as? [String: Any] else { return }

        let id = item["id"] as? String ?? ""
        let title = item["name"] as? String ?? "Unknown"
        let durationMs = item["duration_ms"] as? Int ?? 0
        let artists = (item["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let artist = artists.joined(separator: ", ")
        let albumArt = ((item["album"] as? [String: Any])?["images"] as? [[String: Any]])?.first?["url"] as? String

        // Audio features (BPM/key) are not in currently-playing; fetched separately if needed
        let track = SpotifyTrack(
            id: id,
            title: title,
            artist: artist,
            bpm: nil,
            key: nil,
            durationMs: durationMs,
            albumArtURL: albumArt,
            isPlaying: isPlaying
        )

        await MainActor.run { self.currentTrack = track }
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first { $0.isKeyWindow } ?? NSApplication.shared.windows.first!
    }
}
