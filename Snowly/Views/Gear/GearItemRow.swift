//
//  GearItemRow.swift
//  Snowly
//
//  A single gear item with checkbox toggle and bounce animation.
//

import SwiftUI

struct GearItemRow: View {
    let item: GearItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isChecked ? Color.green : Color.secondary)
                    .symbolEffect(.bounce, value: item.isChecked)

                Text(item.name)
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? .secondary : .primary)

                Spacer()
            }
        }
        .sensoryFeedback(.selection, trigger: item.isChecked)
    }
}
