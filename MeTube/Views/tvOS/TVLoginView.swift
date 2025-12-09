//
//  TVLoginView.swift
//  MeTube
//
//  tvOS-specific login view that guides users to authenticate via iOS app
//

import SwiftUI

#if os(tvOS)
struct TVLoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var isCheckingCloud = false
    @State private var lastCheckTime: Date?
    
    var body: some View {
        VStack(spacing: 50) {
            Spacer()
            
            // App Logo
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 150))
                .foregroundColor(.red)
            
            // App Title
            Text("MeTube")
                .font(.system(size: 76, weight: .bold))
            
            Text("Your distraction-free YouTube feed")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Instructions
            VStack(spacing: 24) {
                Image(systemName: "iphone")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Sign in with your iPhone or iPad")
                    .font(.title)
                    .fontWeight(.semibold)
                
                VStack(spacing: 12) {
                    InstructionRow(number: 1, text: "Open the MeTube app on your iPhone or iPad")
                    InstructionRow(number: 2, text: "Sign in with your Google account")
                    InstructionRow(number: 3, text: "Your login will sync automatically via iCloud")
                }
                .padding(.horizontal, 40)
            }
            .padding(40)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(20)
            
            Spacer()
            
            // Error message
            if let error = authManager.error {
                Text(error)
                    .foregroundColor(.orange)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // Check status button
            Button(action: {
                checkForCloudSync()
            }) {
                HStack {
                    if isCheckingCloud {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isCheckingCloud ? "Checking..." : "Check for Login")
                }
                .font(.title3)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
            }
            .disabled(isCheckingCloud)
            
            if let lastCheck = lastCheckTime {
                Text("Last checked: \(lastCheck, style: .relative)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            // Auto-check on appear
            checkForCloudSync()
        }
    }
    
    private func checkForCloudSync() {
        isCheckingCloud = true
        Task {
            await authManager.reloadFromCloud()
            await MainActor.run {
                isCheckingCloud = false
                lastCheckTime = Date()
            }
        }
    }
}

struct InstructionRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(spacing: 16) {
            Text("\(number)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color.red)
                .clipShape(Circle())
            
            Text(text)
                .font(.title3)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

#Preview {
    TVLoginView()
        .environmentObject(AuthenticationManager())
}
#endif
