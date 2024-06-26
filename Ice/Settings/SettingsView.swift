//
//  SettingsView.swift
//  Ice
//

import SwiftUI

struct SettingsView: View {
    private static let items: [SettingsNavigationItem] = [
        SettingsNavigationItem(
            name: .general,
            icon: .systemSymbol("gearshape")
        ),
        SettingsNavigationItem(
            name: .menuBarAppearance,
            icon: .systemSymbol("paintpalette")
        ),
        SettingsNavigationItem(
            name: .hotkeys,
            icon: .systemSymbol("keyboard")
        ),
        SettingsNavigationItem(
            name: .advanced,
            icon: .systemSymbol("gearshape.2")
        ),
        SettingsNavigationItem(
            name: .updates,
            icon: .systemSymbol("arrow.triangle.2.circlepath.circle")
        ),
        SettingsNavigationItem(
            name: .about,
            icon: .assetCatalog(.iceCubeStroke)
        ),
    ]

    @State private var selection = Self.items[0]

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationTitle(selection.name.localized)
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(Self.items, id: \.self) { item in
                    sidebarItem(item: item)
                }
            }
            .collapsible(false)
        }
        .navigationSplitViewColumnWidth(210)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection.name {
        case .general:
            GeneralSettingsPane()
        case .menuBarAppearance:
            MenuBarAppearanceSettingsPane()
        case .hotkeys:
            HotkeysSettingsPane()
        case .advanced:
            AdvancedSettingsPane()
        case .updates:
            UpdatesSettingsPane()
        case .about:
            AboutSettingsPane()
        }
    }

    @ViewBuilder
    private func sidebarItem(item: SettingsNavigationItem) -> some View {
        Label {
            Text(item.name.localized)
                .font(.title3)
                .padding(.leading, 2)
        } icon: {
            item.icon.view
                .foregroundStyle(.primary)
        }
        .frame(height: 30)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
