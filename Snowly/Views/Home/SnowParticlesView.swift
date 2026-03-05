//
//  SnowParticlesView.swift
//  Snowly
//
//  Ambient snow particle effect rendered via TimelineView + Canvas.
//

import SwiftUI

struct SnowParticlesView: View {
    private struct Particle: Identifiable {
        let id: Int
        let x: CGFloat
        let size: CGFloat
        let speed: Double
        let delay: Double
        let opacity: Double
        let drift: CGFloat
        let phase: Double
    }

    private let particles: [Particle] = (0..<15).map { id in
        Particle(
            id: id,
            x: .random(in: 0...1),
            size: .random(in: 0.8...2.4),
            speed: .random(in: 18...38),
            delay: .random(in: 0...10),
            opacity: .random(in: 0.03...0.22),
            drift: .random(in: 2...10),
            phase: .random(in: 0...(2 * .pi))
        )
    }

    var body: some View {
        GeometryReader { _ in
            TimelineView(.animation(minimumInterval: 1 / 24)) { context in
                Canvas { canvas, size in
                    let now = context.date.timeIntervalSinceReferenceDate
                    for p in particles {
                        let cycle = ((now / p.speed) + p.delay).truncatingRemainder(dividingBy: 1)
                        let y = CGFloat(cycle) * (size.height + 24) - 12
                        let x = p.x * size.width + CGFloat(sin(now + p.phase)) * p.drift
                        let rect = CGRect(
                            x: x - p.size / 2,
                            y: y - p.size / 2,
                            width: p.size,
                            height: p.size
                        )
                        canvas.fill(
                            Path(ellipseIn: rect),
                            with: .color(.secondary.opacity(p.opacity))
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
