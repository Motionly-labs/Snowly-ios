//
//  GearDetailView.swift
//  Snowly
//
//  Shows all items in a gear setup, grouped by category.
//

import SwiftUI
import SwiftData

struct GearDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let setup: GearSetup

    @State private var showingAddItem = false

    private var groupedItems: [(GearCategory, [GearItem])] {
        let grouped = Dictionary(grouping: setup.items) { $0.category }
        return GearCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return (category, items.sorted { $0.sortOrder < $1.sortOrder })
        }
    }

    var body: some View {
        List {
            Section {
                GearProgressBar(progress: setup.progress, itemCount: setup.items.count)
            }

            ForEach(groupedItems, id: \.0) { category, items in
                Section {
                    ForEach(items) { item in
                        GearItemRow(item: item, onToggle: { toggleItem(item) })
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteItem(item)
                                } label: {
                                    Label(String(localized: "common_delete"), systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Label(category.rawValue, systemImage: category.iconName)
                }
            }

            Section {
                Button {
                    uncheckAll()
                } label: {
                    Label(String(localized: "gear_detail_action_uncheck_all"), systemImage: "arrow.counterclockwise")
                }
                .disabled(setup.items.allSatisfy { !$0.isChecked })
            }
        }
        .navigationTitle(setup.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            GearItemEditView(setup: setup, mode: .add)
        }
    }

    private func toggleItem(_ item: GearItem) {
        item.isChecked.toggle()
    }

    private func deleteItem(_ item: GearItem) {
        modelContext.delete(item)
    }

    private func uncheckAll() {
        for item in setup.items {
            item.isChecked = false
        }
    }
}
