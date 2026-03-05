//
//  SegmentedPicker.swift
//  Snowly
//
//  Generic capsule-style segmented picker.
//

import SwiftUI

struct SegmentedPicker<T: Hashable, Label: View>: View {
    let items: [T]
    @Binding var selection: T
    @ViewBuilder let label: (T) -> Label

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let isSelected = selection == item
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = item
                    }
                } label: {
                    label(item)
                        .foregroundStyle(isSelected ? .primary : .tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if isSelected {
                                Capsule().fill(.quaternary)
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: isSelected)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity)
        .background(.quinary, in: Capsule())
    }
}
