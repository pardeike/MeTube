//
//  LoginView.swift
//  MeTube
//
//  Login screen for Google OAuth authentication
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var clientId: String = ""
    @State private var showingConfig: Bool = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()
                
                // App Logo/Icon
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
                
                // App Title
                Text("MeTube")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your distraction-free YouTube feed")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Spacer()
                
                // Features List
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "checkmark.circle.fill", text: "Only videos from your subscriptions")
                    FeatureRow(icon: "clock.fill", text: "Chronological feed, no algorithm")
                    FeatureRow(icon: "xmark.circle.fill", text: "No Shorts, no distractions")
                    FeatureRow(icon: "icloud.fill", text: "Syncs across your devices")
                }
                .padding(.horizontal, 30)
                
                Spacer()
                
                // Error Message
                if let error = authManager.error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Sign In Button
                Button(action: {
                    Task {
                        await authManager.signIn()
                    }
                }) {
                    HStack {
                        Image(systemName: "person.badge.key.fill")
                        Text("Sign in with Google")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(12)
                }
                .disabled(authManager.isLoading)
                .padding(.horizontal, 30)
                
                if authManager.isLoading {
                    ProgressView()
                        .padding()
                }
                
                // Configuration Button
                Button(action: {
                    showingConfig = true
                }) {
                    Text("Configure OAuth")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 20)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingConfig) {
                ConfigurationSheet(clientId: $clientId, authManager: authManager)
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.red)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct ConfigurationSheet: View {
    @Binding var clientId: String
    let authManager: AuthenticationManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("OAuth Configuration")) {
                    TextField("Google Client ID", text: $clientId)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                
                Section(footer: Text("Enter the OAuth 2.0 Client ID from your Google Cloud Console project.")) {
                    Button("Save Configuration") {
                        authManager.configure(clientId: clientId)
                        dismiss()
                    }
                    .disabled(clientId.isEmpty)
                }
            }
            .navigationTitle("Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthenticationManager())
}
