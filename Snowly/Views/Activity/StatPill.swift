//
//  StatPill.swift
//  Snowly
//
//  Stat pill component. Large number + small label.
//

import SwiftUI

struct StatPill: View {
    let value: String
    let label: String
    var isAccented: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(isAccented ? Color.accentColor : .primary)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 16))
    }
}
