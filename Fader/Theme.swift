#if os(macOS)
import SwiftUI

struct Palette {
    var background: Color
    var elevated: Color
    var line: Color
    var text: Color
    var secondary: Color
    var copper: Color
    var copperDeep: Color
    var track: Color
    var danger: Color

    static func forScheme(_ scheme: ColorScheme) -> Palette {
        switch scheme {
        case .dark:
            return Palette(
                background: Color(red: 0.067, green: 0.078, blue: 0.102),
                elevated: Color(red: 0.106, green: 0.118, blue: 0.153),
                line: Color(red: 0.165, green: 0.180, blue: 0.227),
                text: Color(red: 0.953, green: 0.941, blue: 0.910),
                secondary: Color(red: 0.639, green: 0.620, blue: 0.580),
                copper: Color(red: 0.890, green: 0.604, blue: 0.322),
                copperDeep: Color(red: 0.769, green: 0.471, blue: 0.227),
                track: Color(red: 0.145, green: 0.157, blue: 0.196),
                danger: Color(red: 0.886, green: 0.424, blue: 0.365)
            )
        default:
            return Palette(
                background: Color(red: 0.957, green: 0.945, blue: 0.918),
                elevated: Color(red: 0.996, green: 0.988, blue: 0.969),
                line: Color(red: 0.894, green: 0.867, blue: 0.824),
                text: Color(red: 0.110, green: 0.098, blue: 0.082),
                secondary: Color(red: 0.435, green: 0.416, blue: 0.384),
                copper: Color(red: 0.773, green: 0.416, blue: 0.157),
                copperDeep: Color(red: 0.620, green: 0.310, blue: 0.090),
                track: Color(red: 0.886, green: 0.855, blue: 0.804),
                danger: Color(red: 0.690, green: 0.220, blue: 0.180)
            )
        }
    }
}

struct FaderSlider: View {
    @Binding var value: Double
    var accessibilityLabel: String
    var palette: Palette

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let thumb: CGFloat = 14
            let travel = max(width - thumb, 1)
            let x = travel * value
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.track)
                    .frame(height: 4)
                Capsule()
                    .fill(palette.copper)
                    .frame(width: max(4, x + thumb / 2), height: 4)
                Circle()
                    .fill(palette.elevated)
                    .overlay(Circle().stroke(palette.copper, lineWidth: 2))
                    .frame(width: thumb, height: thumb)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { gesture in
                    value = min(1, max(0, gesture.location.x / width))
                }
            )
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue("\(Int((value * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: value = min(1, value + 0.05)
                case .decrement: value = max(0, value - 0.05)
                default: break
                }
            }
        }
        .frame(height: 22)
    }
}

#endif
