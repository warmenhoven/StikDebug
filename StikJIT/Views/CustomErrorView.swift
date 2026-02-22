//
//  CustomErrorView.swift
//  StikJIT
//
//  Created by neoarz on 3/29/25.
//

import SwiftUI

public enum MessageType {
    case error
    case success
    case info
}

struct CustomErrorView: View {
    var title: String
    var message: String
    var onDismiss: () -> Void
    var showButton: Bool = true
    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.8
    var primaryButtonText: String = "OK"
    var secondaryButtonText: String = "Cancel"
    var onPrimaryButtonTap: (() -> Void)? = nil
    var onSecondaryButtonTap: (() -> Void)? = nil
    var showSecondaryButton: Bool = false
    var messageType: MessageType = .error
    
    @AppStorage("customAccentColor") private var customAccentColorHex: String = ""
    
    private var accentColor: Color {
        if customAccentColorHex.isEmpty { return .blue }
        return Color(hex: customAccentColorHex) ?? .blue
    }
    
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .edgesIgnoringSafeArea(.all)
                .opacity(opacity)
                .onTapGesture {
                    if showButton {
                        dismissWithAnimation()
                    }
                }
            
            VStack(spacing: 12) {
                switch messageType {
                case .error:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.red.opacity(0.9))
                        .padding(.top, 8)
                case .success:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green.opacity(0.9))
                        .padding(.top, 8)
                case .info:
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(accentColor.opacity(0.9))
                        .padding(.top, 8)
                }
                
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Rectangle()
                    .frame(height: 1)
                    .foregroundStyle(.primary.opacity(0.2))
                    .padding(.horizontal, 12)

                Text(LocalizedStringKey(message))
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                
                
                if showButton {
                    VStack(spacing: 6) {
                        Button(action: {
                            dismissWithAnimation()
                            onPrimaryButtonTap?()
                        }) {
                            Text(primaryButtonText)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(accentColor.contrastText())
                                .frame(height: 38)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(accentColor)
                                )
                        }
                        
                        if showSecondaryButton {
                            Button(action: {
                                dismissWithAnimation()
                                onSecondaryButtonTap?()
                            }) {
                                Text(secondaryButtonText)
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(height: 38)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(UIColor.secondarySystemFill))
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .padding(.top, 6)
                } else {
                    Spacer()
                        .frame(height: 12)
                }
            }
            .frame(width: min(UIScreen.main.bounds.width - 80, 300))
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.systemGray6).opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                opacity = 1
                scale = 1
            }
        }
    }
    
    private func dismissWithAnimation() {
        withAnimation(.easeOut(duration: 0.18)) {
            opacity = 0
            scale = 0.95
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onDismiss()
        }
    }
} 
