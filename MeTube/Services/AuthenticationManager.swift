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
/// These should match the bundle identifier and URL scheme in Info.plist
enum OAuthConfig {
    /// The app's bundle identifier, used for URL scheme
    static let bundleIdentifier = "com.metube.app"
    
    /// OAuth callback path
    static let callbackPath = "oauth2callback"
    
    /// Full redirect URI for OAuth flow
    static var redirectUri: String {
        return "\(bundleIdentifier):/\(callbackPath)"
    }
    
    /// URL scheme for authentication callbacks
    static var urlScheme: String {
        return bundleIdentifier
    }
    
    /// Google OAuth token endpoint
    static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    
    /// Google OAuth authorization endpoint
    static let authURL = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    
    /// Required OAuth scopes for YouTube read access
    static let scopes = ["https://www.googleapis.com/auth/youtube.readonly"]
}

/// Manages OAuth authentication for YouTube API
class AuthenticationManager: NSObject, ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    private let tokenKey = "com.metube.oauth.token"
    private let refreshTokenKey = "com.metube.oauth.refreshToken"
    private let expirationKey = "com.metube.oauth.expiration"
    
    // Client ID from Google Cloud Console
    // For security, this is stored in UserDefaults after user configuration
    private var clientId: String {
        return UserDefaults.standard.string(forKey: "GoogleClientId") ?? ""
    }
    
    private var webAuthSession: ASWebAuthenticationSession?
    
    override init() {
        super.init()
        loadStoredToken()
    }
    
    // MARK: - Public Methods
    
    /// Checks if user is authenticated and token is valid
    func checkAuthenticationStatus() {
        if let expiration = UserDefaults.standard.object(forKey: expirationKey) as? Date {
            if expiration > Date() {
                isAuthenticated = true
            } else {
                // Token expired, try to refresh
                Task {
                    await refreshTokenIfNeeded()
                }
            }
        } else {
            isAuthenticated = false
        }
    }
    
    /// Returns the current access token, refreshing if necessary
    func getAccessToken() async -> String? {
        // Check if token needs refresh
        if let expiration = UserDefaults.standard.object(forKey: expirationKey) as? Date,
           expiration <= Date() {
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
        
        // Build authorization URL
        var components = URLComponents(url: OAuthConfig.authURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: OAuthConfig.redirectUri),
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
        
        // Create and start authentication session
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: OAuthConfig.urlScheme) { [weak self] callbackURL, error in
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
        UserDefaults.standard.removeObject(forKey: expirationKey)
        isAuthenticated = false
    }
    
    /// Configures the OAuth client ID
    func configure(clientId: String) {
        UserDefaults.standard.set(clientId, forKey: "GoogleClientId")
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
            "redirect_uri": OAuthConfig.redirectUri,
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
    
    private func loadStoredToken() {
        if retrieveToken() != nil {
            checkAuthenticationStatus()
        }
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
        
        // Save expiration date
        let expiration = Date().addingTimeInterval(TimeInterval(expiresIn))
        UserDefaults.standard.set(expiration, forKey: expirationKey)
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
