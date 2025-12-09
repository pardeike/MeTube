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
        VStack(spacing: 30) {
            Spacer()
            
            // App Logo
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 100))
                .foregroundColor(.red)
            
            // App Title
            Text("MeTube")
                .font(.system(size: 52, weight: .bold))
            
            Text("Your distraction-free YouTube feed")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Instructions
            VStack(spacing: 16) {
                Image(systemName: "iphone")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                Text("Sign in with your iPhone or iPad")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                VStack(spacing: 8) {
                    InstructionRow(number: 1, text: "Open the MeTube app on your iPhone or iPad")
                    InstructionRow(number: 2, text: "Sign in with your Google account")
                    InstructionRow(number: 3, text: "Your login will sync automatically via iCloud")
                }
                .padding(.horizontal, 30)
            }
            .padding(30)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(20)
            
            Spacer()
            
            // Error message
            if let error = authManager.error {
                Text(error)
                    .foregroundColor(.orange)
                    .font(.footnote)
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
                .font(.callout)
                .padding(.horizontal, 30)
                .padding(.vertical, 12)
            }
            .disabled(isCheckingCloud)
            
            if let lastCheck = lastCheckTime {
                Text("Last checked: \(lastCheck, style: .relative)")
                    .font(.footnote)
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
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.callout)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.red)
                .clipShape(Circle())
            
            Text(text)
                .font(.callout)
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
