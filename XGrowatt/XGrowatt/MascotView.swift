import SwiftUI

struct MascotView: View {
    var solarKw: Double = 0.0
    var chargeKw: Double = 0.0
    var dischargeKw: Double = 0.0
    var loadKw: Double = 0.0
    var gridExportKw: Double = 0.0
    var gridImportKw: Double = 0.0
    var socPct: Int = 80
    var weatherIcon: String = "sunny"
    var skin: String = "slime"
    var size: CGFloat = 46.0

    @State private var isBreathing = false
    @State private var blinkEyes = false

    private var mascotColor: Color {
        switch skin.lowercased() {
        case "blob":
            return Theme.solarGold
        case "robot":
            return Color(red: 0.2, green: 0.7, blue: 0.9)
        case "cyber":
            return Theme.gridPurple
        case "pet":
            return Color(red: 1.0, green: 0.5, blue: 0.7)
        default:
            return Theme.batteryGreen // Slime
        }
    }

    var body: some View {
        ZStack {
            // Subtle inner aura (tight, no bleed)
            Circle()
                .fill(mascotColor.opacity(0.18))
                .frame(width: size * 1.05, height: size * 1.05)
                .blur(radius: 2)

            // Mascot Body
            RoundedRectangle(cornerRadius: size * 0.35)
                .fill(
                    LinearGradient(
                        colors: [mascotColor.opacity(0.9), mascotColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .scaleEffect(y: isBreathing ? 1.05 : 0.95)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.35)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )

            // Face Details (Eyes & Smile)
            VStack(spacing: 3) {
                HStack(spacing: size * 0.2) {
                    // Left Eye
                    Capsule()
                        .fill(Color.white)
                        .frame(width: size * 0.16, height: blinkEyes ? size * 0.03 : size * 0.22)
                    
                    // Right Eye
                    Capsule()
                        .fill(Color.white)
                        .frame(width: size * 0.16, height: blinkEyes ? size * 0.03 : size * 0.22)
                }

                // Cute Smile
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addQuadCurve(to: CGPoint(x: size * 0.22, y: 0), control: CGPoint(x: size * 0.11, y: size * 0.12))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: size * 0.22, height: size * 0.1)
            }
            .offset(y: -size * 0.04)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
            
            // Random eye blink timer
            Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    blinkEyes = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        blinkEyes = false
                    }
                }
            }
        }
    }
}
