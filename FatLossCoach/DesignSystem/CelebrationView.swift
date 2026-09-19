import SwiftUI

/// A brief, tasteful reward moment for genuine wins (goal met, streak) — a checkmark burst with
/// a ring of particles. Auto-dismisses (the Store clears `celebration` after ~1.6s).
struct CelebrationView: View {
    let text: String
    @State private var pop = false
    @State private var burst = false

    private let colors: [Color] = [Theme.primary, Theme.primaryLight, Theme.orange, Theme.blue]

    var body: some View {
        ZStack {
            // particle ring
            ForEach(0..<14, id: \.self) { i in
                let angle = Double(i) / 14 * 2 * .pi
                Circle()
                    .fill(colors[i % colors.count])
                    .frame(width: 8, height: 8)
                    .offset(x: burst ? cos(angle) * 90 : 0, y: burst ? sin(angle) * 90 : 0)
                    .opacity(burst ? 0 : 1)
            }
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.primary).frame(width: 76, height: 76)
                        .shadow(color: Theme.primary.opacity(0.6), radius: 14)
                    Image(systemName: "checkmark").font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(Color(hex: 0x101518))
                }
                .scaleEffect(pop ? 1 : 0.3)
                Text(text).font(.system(size: 15, weight: .heavy)).foregroundStyle(.white)
                    .opacity(pop ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { pop = true }
            withAnimation(.easeOut(duration: 0.9)) { burst = true }
        }
    }
}
