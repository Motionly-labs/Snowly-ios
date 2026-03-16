//
//  GearCategoryPickerView.swift
//  Snowly
//
//  Two-level grouped picker for selecting a GearAssetCategory.
//  First level: body-part groups. Second level: specific categories within each group.
//

import SwiftUI

struct GearCategoryPickerView: View {
    @Binding var selection: GearAssetCategory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(GearAssetCategory.Group.allCases) { group in
                Section {
                    ForEach(group.categories, id: \.self) { category in
                        Button {
                            selection = category
                            dismiss()
                        } label: {
                            HStack {
                                Label(category.rawValue, systemImage: category.iconName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if category == selection {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(ColorTokens.primaryAccent)
                                }
                            }
                        }
                    }
                } header: {
                    Label(group.rawValue, systemImage: group.iconName)
                }
            }
        }
        .navigationTitle("Category")
        .navigationBarTitleDisplayMode(.inline)
    }
}
