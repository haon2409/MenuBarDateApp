import Foundation
import AuthenticationServices
import CryptoKit
import AppKit
import Combine

@MainActor
final class GoogleAuthManager: NSObject, ObservableObject {
    static let shared = GoogleAuthManager()
    
    @Published var isLoggedIn = false
    @Published var accessToken: String?
    
    private let clientID = "755541392936-hao1n89s0gpmb9am1maphkie44svgve8.apps.googleusercontent.com"
    private let redirectURI = "Mimosa.MenuBarDateApp:/oauthredirect"
    private let scopes = [
        "https://www.googleapis.com/auth/calendar",
        "https://www.googleapis.com/auth/tasks",
        "https://www.googleapis.com/auth/userinfo.profile"
    ].joined(separator: " ")
    
    private var codeVerifier = ""
    private var authSession: ASWebAuthenticationSession?
    
    // Lưu thời điểm hết hạn access token (có buffer 60s)
    private var tokenExpiresAt: Date?
    
    private override init() {
        super.init()
        restoreToken()
    }
    
    // MARK: - Login
    func login() {
        codeVerifier = Self.generateCodeVerifier()
        let challenge = Self.codeChallenge(from: codeVerifier)
        
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]
        
        guard let authURL = components.url else { return }
        
        authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "Mimosa.MenuBarDateApp"
        ) { [weak self] callbackURL, error in
            guard let self, error == nil, let callbackURL else {
                print("Auth error:", error?.localizedDescription ?? "unknown")
                return
            }
            Task { await self.handleCallback(callbackURL) }
        }
        
        authSession?.presentationContextProvider = self
        authSession?.prefersEphemeralWebBrowserSession = false
        authSession?.start()
    }
    
    private func handleCallback(_ url: URL) async {
        guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else { return }
        
        await exchangeCodeForToken(code: code)
    }
    
    private func exchangeCodeForToken(code: String) async {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": clientID,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)" }
         .joined(separator: "&")
        
        request.httpBody = body.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let access = json?["access_token"] as? String {
                accessToken = access
                isLoggedIn = true
                
                // Lưu expires_at
                if let expiresIn = json?["expires_in"] as? Int {
                    tokenExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn - 60))
                    if let expiresData = "\(tokenExpiresAt!.timeIntervalSince1970)".data(using: .utf8) {
                        _ = KeychainHelper.save(key: "token_expires_at", data: expiresData)
                    }
                }
                
                if let refresh = json?["refresh_token"] as? String,
                   let data = refresh.data(using: .utf8) {
                    _ = KeychainHelper.save(key: "refresh_token", data: data)
                }
                if let data = access.data(using: .utf8) {
                    _ = KeychainHelper.save(key: "access_token", data: data)
                }
            } else {
                print("Token response:", String(data: data, encoding: .utf8) ?? "")
            }
        } catch {
            print("Token exchange error:", error)
        }
    }
    
    // MARK: - Refresh Token
    func refreshAccessTokenIfNeeded(forceRefresh: Bool = false) async -> String? {
        // Còn hạn + không force → dùng luôn
        if !forceRefresh,
           let token = accessToken,
           let expiresAt = tokenExpiresAt,
           Date() < expiresAt {
            return token
        }
        
        guard let refreshData = KeychainHelper.load(key: "refresh_token"),
              let refreshToken = String(data: refreshData, encoding: .utf8) else {
            logout()
            return nil
        }
        
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyDict = [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        let body = bodyDict
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        
        request.httpBody = body.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                print("Refresh HTTP \(http.statusCode):", String(data: data, encoding: .utf8) ?? "")
                logout()
                return nil
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let access = json?["access_token"] as? String {
                accessToken = access
                isLoggedIn = true
                
                // Cập nhật expires_at
                if let expiresIn = json?["expires_in"] as? Int {
                    tokenExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn - 60))
                    if let expiresData = "\(tokenExpiresAt!.timeIntervalSince1970)".data(using: .utf8) {
                        _ = KeychainHelper.save(key: "token_expires_at", data: expiresData)
                    }
                }
                
                // Đôi khi Google trả refresh_token mới
                if let newRefresh = json?["refresh_token"] as? String,
                   let d = newRefresh.data(using: .utf8) {
                    _ = KeychainHelper.save(key: "refresh_token", data: d)
                }
                
                if let d = access.data(using: .utf8) {
                    _ = KeychainHelper.save(key: "access_token", data: d)
                }
                return access
            } else {
                // invalid_grant hoặc lỗi khác
                print("Refresh failed:", String(data: data, encoding: .utf8) ?? "")
                logout()
            }
        } catch {
            print("Refresh error:", error)
            logout()
        }
        return nil
    }
    
    func logout() {
        accessToken = nil
        isLoggedIn = false
        tokenExpiresAt = nil
        KeychainHelper.delete(key: "access_token")
        KeychainHelper.delete(key: "refresh_token")
        KeychainHelper.delete(key: "token_expires_at")
    }
    
    private func restoreToken() {
        // Chỉ coi là logged in khi còn refresh_token
        guard let refreshData = KeychainHelper.load(key: "refresh_token"),
              String(data: refreshData, encoding: .utf8) != nil else {
            isLoggedIn = false
            accessToken = nil
            tokenExpiresAt = nil
            return
        }
        
        isLoggedIn = true
        
        if let data = KeychainHelper.load(key: "access_token"),
           let token = String(data: data, encoding: .utf8) {
            accessToken = token
        }
        
        if let expiresData = KeychainHelper.load(key: "token_expires_at"),
           let expiresStr = String(data: expiresData, encoding: .utf8),
           let timestamp = Double(expiresStr) {
            tokenExpiresAt = Date(timeIntervalSince1970: timestamp)
        }
    }
    
    func fetchProfileImageURL() async -> URL? {
        // Luôn refresh trước để đảm bảo token còn sống
        guard let token = await refreshAccessTokenIfNeeded() else {
            return nil
        }
        
        let url = URL(string: "https://www.googleapis.com/oauth2/v1/userinfo")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let urlString = json?["picture"] as? String {
                return URL(string: urlString)
            }
        } catch {
            print("❌ [GoogleAuth] Error fetching profile image: \(error)")
        }
        return nil
    }
    
    // MARK: - PKCE helpers
    private static func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private static func codeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension GoogleAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
