import SwiftUI

struct ElectronicLevelView: View {
    let reading: LevelReading
    let size: LevelSize
    var body: some View {
        Canvas { context, bounds in
            let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
            let radius = min(bounds.width, bounds.height) * 0.44
            let color: Color = reading.isLevel ? .green : .white
            var arcs = Path()
            arcs.addArc(center: center, radius: radius, startAngle: .degrees(145), endAngle: .degrees(215), clockwise: false)
            arcs.move(to: CGPoint(x: center.x + radius * cos(-.pi/5), y: center.y + radius * sin(-.pi/5)))
            arcs.addArc(center: center, radius: radius, startAngle: .degrees(-35), endAngle: .degrees(35), clockwise: false)
            context.stroke(arcs, with: .color(.white), lineWidth: 1)
            var moving = context
            moving.translateBy(x: center.x, y: center.y)
            moving.rotate(by: .degrees(reading.roll))
            let dy = CGFloat(max(-20, min(20, reading.pitch))) / 20 * radius * 0.6
            var line = Path()
            line.move(to: CGPoint(x: -radius, y: dy)); line.addLine(to: CGPoint(x: -12, y: dy))
            line.move(to: CGPoint(x: 12, y: dy)); line.addLine(to: CGPoint(x: radius, y: dy))
            moving.stroke(line, with: .color(color), lineWidth: 1.5)
            var marks = Path()
            marks.addRect(CGRect(x: center.x-4, y: center.y-2, width: 8, height: 4))
            for offset: CGFloat in [-18,18] { marks.move(to: CGPoint(x: center.x-6, y: center.y+offset)); marks.addLine(to: CGPoint(x: center.x+6, y: center.y+offset)) }
            context.stroke(marks, with: .color(color), lineWidth: 1)
        }.frame(width: size == .large ? 220 : 120, height: size == .large ? 150 : 90)
            .allowsHitTesting(false).accessibilityElement().accessibilityLabel("電子水平儀")
            .accessibilityValue(reading.isLevel ? "水平" : String(format: "傾斜 %.1f，俯仰 %.1f", reading.roll, reading.pitch))
            .accessibilityIdentifier("camera.level")
    }
}
