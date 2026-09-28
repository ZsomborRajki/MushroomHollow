import GameCore
import SwiftUI

/// Shared chrome for full-screen panels: dimmed backdrop, glass card, title bar.
private struct PanelChrome<Content: View>: View {
    let title: String
    let subtitle: String?
    let glyphs: ControllerGlyphs?
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title2.weight(.bold))
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Label("Close", systemImage: glyphs?.back ?? "xmark")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
            }
            content
        }
        .padding(20)
        .frame(maxWidth: 720, maxHeight: 380)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.35))
    }
}

/// A button showing the controller glyph that triggers it.
private struct ActionButton: View {
    let title: String
    let glyph: String?
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: glyph ?? "hand.tap.fill")
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.green.opacity(isEnabled ? 0.35 : 0)).interactive(), in: .capsule)
        .opacity(isEnabled ? 1 : 0.4)
        .disabled(!isEnabled)
    }
}

// MARK: - Inventory

struct InventoryPanel: View {
    let session: GameSession

    private let cellSize: CGFloat = 46
    private let columns = GameSession.inventoryColumns

    var body: some View {
        let cells = session.inventoryCells
        let player = session.hud.player
        let selected = cells.first { $0.id == session.selection }

        PanelChrome(title: "Bag", subtitle: player.map { "\($0.caps) caps" }, glyphs: session.glyphs, onClose: session.closePanel) {
            HStack(alignment: .top, spacing: 14) {
                // Equipment column, then the bag grid; matches controller navigation.
                VStack(spacing: 6) {
                    ForEach(cells.prefix(GameSession.firstBagCell)) { cell($0) }
                }
                Divider()
                let bag = Array(cells.dropFirst(GameSession.firstBagCell))
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(0..<(bag.count / columns), id: \.self) { row in
                        GridRow {
                            ForEach(bag[(row * columns)..<((row + 1) * columns)]) { cell($0) }
                        }
                    }
                }
                ItemDetail(cell: selected, player: player, glyph: session.glyphs?.primary) {
                    session.perform(.menu(.confirm))
                }
            }
        }
    }

    private func cell(_ cell: InventoryCell) -> some View {
        let isSelected = cell.id == session.selection
        return Button { session.tapSelection(cell.id) } label: {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.25))
                if let item = cell.item {
                    Image(systemName: item.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(item.tint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if cell.count > 1 {
                        Text("\(cell.count)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .padding(3)
                    }
                } else if let slot = cell.slot {
                    Image(systemName: slot.placeholderSymbol)
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.2))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: cellSize, height: cellSize)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.yellow : (cell.slot != nil ? .white.opacity(0.35) : .clear), lineWidth: isSelected ? 3 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ItemDetail: View {
    let cell: InventoryCell?
    let player: PlayerStatus?
    let glyph: String?
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cell, let item = cell.item {
                let definition = item.definition
                HStack(spacing: 10) {
                    Image(systemName: item.symbol)
                        .font(.title)
                        .foregroundStyle(item.tint)
                    VStack(alignment: .leading) {
                        Text(definition.name).font(.headline)
                        if let line = item.statLine {
                            Text(line).font(.caption.weight(.semibold)).foregroundStyle(.green)
                        }
                    }
                }
                Text(definition.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if definition.requiredLevel > 1 {
                    let tooLow = (player?.stats.level ?? 0) < definition.requiredLevel
                    Text("Requires Lv \(definition.requiredLevel)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tooLow ? .red : .secondary)
                }
                Text("Sells for \(definition.sellPrice) caps").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                switch (cell.slot, definition.kind) {
                case (.some, _): ActionButton(title: "Unequip", glyph: glyph, isEnabled: true, action: action)
                case (nil, .equipment): ActionButton(title: "Equip", glyph: glyph, isEnabled: true, action: action)
                case (nil, .consumable): ActionButton(title: "Use", glyph: glyph, isEnabled: true, action: action)
                case (nil, .glider): ActionButton(title: "Fly", glyph: glyph, isEnabled: true, action: action)
                case (nil, .material): EmptyView()
                }
            } else {
                Text(cell?.slot.map { "No \($0.displayName.lowercased()) equipped" } ?? "Empty slot")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let stats = player?.stats {
                Divider()
                HStack(spacing: 14) {
                    stat("ATK", stats.attack)
                    stat("DEF", stats.defense)
                    stat("HP", stats.maxHP)
                    stat("MP", stats.maxMP)
                }
            }
        }
        .frame(width: 230, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func stat(_ name: String, _ value: Int) -> some View {
        VStack(spacing: 0) {
            Text(name).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text("\(value)").font(.callout.weight(.semibold).monospacedDigit())
        }
    }
}

// MARK: - NPC

struct NPCPanel: View {
    let session: GameSession
    let npc: NPCID

    var body: some View {
        let definition = npc.definition
        let rows = session.npcRows
        let selected = rows.indices.contains(session.selection) ? rows[session.selection] : nil

        PanelChrome(title: definition.name, subtitle: definition.title, glyphs: session.glyphs, onClose: session.closePanel) {
            VStack(alignment: .leading, spacing: 12) {
                Text(definition.greeting)
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
                if definition.isShopkeeper {
                    HStack(spacing: 8) {
                        if let glyph = session.glyphs?.previousTarget { Image(systemName: glyph) }
                        Picker("Mode", selection: Binding(get: { session.shopTab }, set: { session.setShopTab($0) })) {
                            Text("Buy").tag(ShopTab.buy)
                            Text("Sell").tag(ShopTab.sell)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        if let glyph = session.glyphs?.nextTarget { Image(systemName: glyph) }
                        Spacer()
                        if let caps = session.hud.player?.caps {
                            Label("\(caps)", systemImage: "circle.circle.fill")
                                .foregroundStyle(.yellow)
                                .font(.callout.weight(.semibold).monospacedDigit())
                        }
                    }
                }
                HStack(alignment: .top, spacing: 16) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 6) {
                                if rows.isEmpty {
                                    Text(definition.isShopkeeper ? "Nothing to sell." : "No tasks right now. Come back later!")
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                    RowView(row: row, isSelected: index == session.selection)
                                        .id(index)
                                        .onTapGesture { session.tapSelection(index) }
                                }
                            }
                        }
                        .onChange(of: session.selection) { _, new in
                            withAnimation { proxy.scrollTo(new, anchor: .center) }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 10) {
                        if let selected {
                            Text(selected.title).font(.headline)
                            Text(selected.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            if selected.action != .none {
                                ActionButton(title: actionTitle(selected.action), glyph: session.glyphs?.primary,
                                             isEnabled: selected.isEnabled) {
                                    session.perform(.menu(.confirm))
                                }
                            }
                        }
                    }
                    .frame(width: 240, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    private func actionTitle(_ action: PanelRow.Action) -> String {
        switch action {
        case .buy: "Buy"
        case .sell: "Sell 1"
        case .accept: "Accept"
        case .turnIn: "Turn in"
        case .chooseClass: "Choose this path"
        case .none: ""
        }
    }
}

private struct RowView: View {
    let row: PanelRow
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: row.symbol)
                .font(.title3)
                .foregroundStyle(row.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.subheadline.weight(.semibold))
                if !row.subtitle.isEmpty {
                    Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(row.trailing)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(row.isEnabled ? .yellow : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(isSelected ? 0.35 : 0.15), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? Color.yellow : .clear, lineWidth: 2)
        }
        .opacity(row.isEnabled ? 1 : 0.6)
        .contentShape(Rectangle())
    }
}

// MARK: - World prompts

/// "Talk to Elder Morel" when standing next to an NPC.
struct InteractPrompt: View {
    let npc: NPCID
    let glyph: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Talk to \(npc.definition.name)", systemImage: glyph ?? npc.symbol)
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.yellow.opacity(0.25)).interactive(), in: .capsule)
    }
}
