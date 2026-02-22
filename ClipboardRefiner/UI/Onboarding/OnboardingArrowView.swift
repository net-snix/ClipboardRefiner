import SwiftUI

struct OnboardingArrowView: View {
    let statusItemFrame: CGRect
    let onDismiss: () -> Void

    @State private var arrowOffset: CGFloat = 0
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ArrowShape()
                    .fill(Color.white)
                    .frame(width: 36, height: 54)
                    .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                    .offset(y: arrowOffset)

                VStack(spacing: 8) {
                    Text("Click here to get started")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Tap anywhere to dismiss")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .position(
                x: statusItemFrame.midX,
                y: statusItemFrame.maxY + 80
            )
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.3)) {
                opacity = 1
            }
            withAnimation(
                .easeInOut(duration: 0.9)
                .repeatForever(autoreverses: true)
            ) {
                arrowOffset = -10
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                opacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                onDismiss()
            }
        }
    }
}

private struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let arrowWidth = rect.width
        let arrowHeight = rect.height
        let headHeight = arrowHeight * 0.5
        let stemWidth = arrowWidth * 0.35

        // Arrow pointing UP
        // Tip of arrow
        path.move(to: CGPoint(x: arrowWidth / 2, y: 0))

        // Left side of head
        path.addLine(to: CGPoint(x: 0, y: headHeight))

        // Left inner corner
        path.addLine(to: CGPoint(x: (arrowWidth - stemWidth) / 2, y: headHeight))

        // Left side of stem
        path.addLine(to: CGPoint(x: (arrowWidth - stemWidth) / 2, y: arrowHeight))

        // Bottom of stem
        path.addLine(to: CGPoint(x: (arrowWidth + stemWidth) / 2, y: arrowHeight))

        // Right side of stem
        path.addLine(to: CGPoint(x: (arrowWidth + stemWidth) / 2, y: headHeight))

        // Right inner corner
        path.addLine(to: CGPoint(x: arrowWidth, y: headHeight))

        // Back to tip
        path.closeSubpath()

        return path
    }
}

#if DEBUG
struct OnboardingArrowView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingArrowView(
            statusItemFrame: CGRect(x: 200, y: 0, width: 30, height: 22),
            onDismiss: {}
        )
        .frame(width: 400, height: 300)
        .background(Color.gray)
    }
}
#endif
