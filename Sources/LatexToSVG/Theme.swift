import SwiftUI

/// The app's small design vocabulary, drawn from mathematical publishing:
/// a sheet of paper on a drafting desk, with one journal-spine red accent.
enum Theme {
    /// Carmine -- the red of classic journal spines. The only accent colour;
    /// replaces the default blue tint everywhere.
    static let accent = Color(red: 0.62, green: 0.19, blue: 0.165)

    /// Warm paper for the equation sheet -- just off pure white, so the sheet
    /// reads as material rather than as empty screen.
    static let paperLight = Color(red: 0.992, green: 0.988, blue: 0.976)

    /// Slate paper, used when the equation colour is too light for white.
    static let paperDark = Color(red: 0.16, green: 0.16, blue: 0.18)
}

/// The drafting-desk surface the paper sheet floats on: the window background
/// with a quiet dot grid, the graph paper of the trade.
struct DeskBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Canvas { context, size in
                let step: CGFloat = 18
                var dots = Path()
                for x in stride(from: step / 2, to: size.width, by: step) {
                    for y in stride(from: step / 2, to: size.height, by: step) {
                        dots.addEllipse(in: CGRect(x: x - 0.75, y: y - 0.75,
                                                   width: 1.5, height: 1.5))
                    }
                }
                context.fill(dots, with: .color(.primary.opacity(0.06)))
            }
        }
    }
}
