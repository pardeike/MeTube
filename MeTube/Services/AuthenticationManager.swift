//
//  AuthenticationManager.swift
//  MeTube
//
//  Manages Google OAuth authentication for YouTube API access
//

import Foundation
import AuthenticationServices
import Security

// MARK: - OAuth Configuration

/// OAuth configuration constants
/// For Google OAuth on iOS, the redirect URI must use the reversed client ID as the URL scheme
enum OAuthConfig {
    /// OAuth callback path
    static let callbackPath = "oauth2callback"
    
    /// Google OAuth token endpoint
    static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    
    /// Google OAuth authorization endpoint
    static let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    
    /// Required OAuth scopes for YouTube read access
    static let scopes = ["https://www.googleapis.com/auth/youtube.readonly"]
    
    /// Derives the reversed client ID from the full client ID
    /// For example: "123456789012-abcdef.apps.googleusercontent.com" becomes "com.googleusercontent.apps.123456789012-abcdef"
    static func reversedClientId(from clientId: String) -> String {
        let components = clientId.split(separator: ".").map(String.init)
        return components.reversed().joined(separator: ".")
    }
    
    /// Full redirect URI for OAuth flow using reversed client ID
    /// Format: {reversed_client_id}:/oauth2callback
    static func redirectUri(for clientId: String) -> String {
        return "\(reversedClientId(from: clientId)):/\(callbackPath)"
    }
    
    /// URL scheme for authentication callbacks (reversed client ID)
    static func urlScheme(for clientId: String) -> String {
        return reversedClientId(from: clientId)
    }
}

/// Manages OAuth authentication for YouTube API
class AuthenticationManager: NSObject, ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    private let tokenKey = "com.metube.oauth.token"
    private let refreshTokenKey = "com.metube.oauth.refreshToken"
    
    // Client ID from Google Cloud Console - stored in CloudKit for cross-device sync
    private var _clientId: String = ""
    private var clientId: String {
        return _clientId
    }
    
    // Token expiration - stored in CloudKit for cross-device sync
    private var tokenExpiration: Date?
    
    // Cached app settings to avoid redundant CloudKit fetches
    private var cachedAppSettings: AppSettings?
    
    private var webAuthSession: ASWebAuthenticationSession?
    private let cloudKitService = CloudKitService()

    @MainActor
    override init() {
        super.init()
        // Load settings from CloudKit asynchronously
        Task {
            await loadSettingsFromCloudKit()
            loadStoredToken()
        }
    }
    
    // MARK: - CloudKit Settings
    
    @MainActor
    private func loadSettingsFromCloudKit() async {
        do {
            if let settings = try await cloudKitService.fetchAppSettings() {
                cachedAppSettings = settings
                _clientId = settings.googleClientId ?? ""
                tokenExpiration = settings.tokenExpiration
                appLog("Loaded auth settings from CloudKit", category: .cloudKit, level: .success)
            }
        } catch {
            appLog("Failed to load auth settings from CloudKit: \(error)", category: .cloudKit, level: .error)
        }
    }
    
    private func saveSettingsToCloudKit() async {
        do {
            // Use cached settings to avoid redundant fetches
            var settings = cachedAppSettings ?? .default
            settings.googleClientId = _clientId
            settings.tokenExpiration = tokenExpiration
            try await cloudKitService.saveAppSettings(settings)
            cachedAppSettings = settings
            appLog("Saved auth settings to CloudKit", category: .cloudKit, level: .success)
        } catch {
            appLog("Failed to save auth settings to CloudKit: \(error)", category: .cloudKit, level: .error)
        }
    }
    
    // MARK: - Public Methods
    
    /// Checks if user is authenticated and token is valid
    @MainActor
    func checkAuthenticationStatus() {
        // First check if we have a refresh token - if so, we can get a new access token
        if retrieveRefreshToken() != nil {
            // We have a refresh token, so we're authenticated (can refresh when needed)
            if let expiration = tokenExpiration, expiration > Date() {
                // Token is still valid
                isAuthenticated = true
            } else {
                // Token expired or unknown, but we have refresh token - try to refresh
                // Set authenticated to true to show the app while refreshing in background.
                // If refresh fails, refreshTokenIfNeeded() will set isAuthenticated = false
                // and display an error message asking the user to sign in again.
                isAuthenticated = true
                Task { @MainActor in
                    await refreshTokenIfNeeded()
                }
            }
        } else if let expiration = tokenExpiration, expiration > Date() {
            // We have a valid token expiration but no refresh token (shouldn't happen normally)
            isAuthenticated = retrieveToken() != nil
        } else {
            isAuthenticated = false
        }
    }
    
    /// Returns the current access token, refreshing if necessary
    func getAccessToken() async -> String? {
        // Check if token needs refresh
        if let expiration = tokenExpiration, expiration <= Date() {
            await refreshTokenIfNeeded()
        }
        
        return retrieveToken()
    }
    
    /// Initiates the OAuth sign-in flow
    @MainActor
    func signIn() async {
        guard !clientId.isEmpty else {
            error = "Google Client ID not configured. Please set up OAuth credentials."
            return
        }
        
        isLoading = true
        error = nil
        
        // Build authorization URL using reversed client ID for redirect URI
        let redirectUri = OAuthConfig.redirectUri(for: clientId)
        var components = URLComponents(url: OAuthConfig.authURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: OAuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        guard let authURL = components.url else {
            isLoading = false
            error = "Failed to create authorization URL"
            return
        }
        
        // Create and start authentication session with reversed client ID as URL scheme
        let urlScheme = OAuthConfig.urlScheme(for: clientId)
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: urlScheme) { [weak self] callbackURL, error in
            Task { @MainActor in
                await self?.handleAuthCallback(callbackURL: callbackURL, error: error)
            }
        }
        
        webAuthSession = session
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        
        session.start()
    }
    
    /// Signs out the user
    @MainActor
    func signOut() {
        deleteToken()
        tokenExpiration = nil
        isAuthenticated = false
        Task {
            await saveSettingsToCloudKit()
        }
    }
    
    /// Configures the OAuth client ID
    func configure(clientId: String) {
        _clientId = clientId
        Task {
            await saveSettingsToCloudKit()
        }
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func handleAuthCallback(callbackURL: URL?, error: Error?) async {
        isLoading = false
        
        if let error = error {
            self.error = error.localizedDescription
            return
        }
        
        guard let callbackURL = callbackURL,
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            self.error = "Failed to get authorization code"
            return
        }
        
        // Exchange code for tokens
        await exchangeCodeForToken(code: code)
    }
    
    private func exchangeCodeForToken(code: String) async {
        var request = URLRequest(url: OAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "code": code,
            "client_id": clientId,
            "redirect_uri": OAuthConfig.redirectUri(for: clientId),
            "grant_type": "authorization_code"
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(TokenResponse.self, from: data)
            
            await MainActor.run {
                saveToken(accessToken: response.access_token, refreshToken: response.refresh_token, expiresIn: response.expires_in)
                isAuthenticated = true
            }
        } catch {
            await MainActor.run {
                self.error = "Failed to exchange authorization code: \(error.localizedDescription)"
            }
        }
    }
    
    private func refreshTokenIfNeeded() async {
        guard let refreshToken = retrieveRefreshToken() else {
            await MainActor.run {
                isAuthenticated = false
            }
            return
        }
        
        var request = URLRequest(url: OAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "refresh_token": refreshToken,
            "client_id": clientId,
            "grant_type": "refresh_token"
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(TokenResponse.self, from: data)
            
            await MainActor.run {
                saveToken(accessToken: response.access_token, refreshToken: response.refresh_token ?? refreshToken, expiresIn: response.expires_in)
                isAuthenticated = true
            }
        } catch {
            await MainActor.run {
                isAuthenticated = false
                self.error = "Failed to refresh token. Please sign in again."
            }
        }
    }
    
    // MARK: - Token Storage (Keychain)
    
    @MainActor private func loadStoredToken() {
        // Check authentication status - this handles both access tokens and refresh tokens
        checkAuthenticationStatus()
    }
    
    private func saveToken(accessToken: String, refreshToken: String?, expiresIn: Int) {
        // Save access token to Keychain
        let tokenData = accessToken.data(using: .utf8)!
        let tokenQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: tokenData
        ]
        
        SecItemDelete(tokenQuery as CFDictionary)
        SecItemAdd(tokenQuery as CFDictionary, nil)
        
        // Save refresh token if provided
        if let refreshToken = refreshToken {
            let refreshData = refreshToken.data(using: .utf8)!
            let refreshQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: refreshTokenKey,
                kSecValueData as String: refreshData
            ]
            
            SecItemDelete(refreshQuery as CFDictionary)
            SecItemAdd(refreshQuery as CFDictionary, nil)
        }
        
        // Save expiration date to CloudKit
        tokenExpiration = Date().addingTimeInterval(TimeInterval(expiresIn))
        Task {
            await saveSettingsToCloudKit()
        }
    }
    
    private func retrieveToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return token
    }
    
    private func retrieveRefreshToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: refreshTokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return token
    }
    
    private func deleteToken() {
        let tokenQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKey
        ]
        SecItemDelete(tokenQuery as CFDictionary)
        
        let refreshQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: refreshTokenKey
        ]
        SecItemDelete(refreshQuery as CFDictionary)
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension AuthenticationManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}

// MARK: - Token Response

private struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
    let token_type: String
}
