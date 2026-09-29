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
                // Equipment paper doll, then the bag grid; matches controller navigation.
                let slots = Array(cells.prefix(GameSession.firstBagCell))
                let slotColumns = GameSession.equipmentColumns
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(0..<(slots.count / slotColumns), id: \.self) { row in
                        GridRow {
                            ForEach(slots[(row * slotColumns)..<((row + 1) * slotColumns)]) { cell($0) }
                        }
                    }
                    if let pet = cells.last, pet.isPetSlot {
                        GridRow { cell(pet).gridCellColumns(slotColumns) }
                    }
                }
                Divider()
                let bag = Array(cells.dropFirst(GameSession.firstBagCell).prefix(Inventory.capacity))
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(0..<(bag.count / columns), id: \.self) { row in
                        GridRow {
                            ForEach(bag[(row * columns)..<((row + 1) * columns)]) { cell($0) }
                        }
                    }
                }
                ItemDetail(cell: selected, player: player, glyph: session.glyphs?.primary, onUnslotPet: session.unslotPet) {
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
                    if cell.upgrade > 0 {
                        Text("+\(cell.upgrade)")
                            .font(.caption2.weight(.heavy).monospacedDigit())
                            .foregroundStyle(Color(red: 1, green: 0.75, blue: 0.3))
                            .padding(3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else if cell.isPetSlot || cell.slot != nil {
                    Image(systemName: cell.slot?.placeholderSymbol ?? "pawprint")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.2))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: cellSize, height: cellSize)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.yellow : border(cell), lineWidth: isSelected ? 3 : 1)
            }
            .overlay(alignment: .topTrailing) {
                // Out and following: a green dot (red while hungry).
                if cell.isPetSlot, let pet = session.hud.player?.pet, pet.isSummoned || pet.awaitingFood {
                    Circle()
                        .fill(pet.isHungry || pet.awaitingFood ? Color.red : Color.green)
                        .frame(width: 9, height: 9)
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Set pieces and boss drops get a colored rim; empty equipment slots a faint one.
    private func border(_ cell: InventoryCell) -> Color {
        switch cell.item?.definition.rarity {
        case .set, .unique: cell.item!.definition.rarity.color.opacity(0.8)
        default: cell.slot != nil || cell.isPetSlot ? .white.opacity(0.35) : .clear
        }
    }
}

private struct ItemDetail: View {
    let cell: InventoryCell?
    let player: PlayerStatus?
    let glyph: String?
    let onUnslotPet: () -> Void
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let cell, let item = cell.item, let gear = cell.gear {
                let definition = item.definition
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol)
                                .font(.title)
                                .foregroundStyle(item.tint)
                            VStack(alignment: .leading) {
                                Text(gear.displayName).font(.headline).foregroundStyle(definition.rarity.color)
                                if let line = item.gearLine {
                                    Text(line).font(.caption).foregroundStyle(.secondary)
                                }
                                if let line = gear.statLine {
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
                        if let required = definition.requiredClass, player?.playerClass != required {
                            Text("Requires \(required.definition.name)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                        if let set = definition.set {
                            SetSummary(set: set, worn: player.map { set.worn(in: $0.equipment) } ?? 0)
                        }
                        if let pet = player?.pet, cell.isPetSlot || item == .kibble {
                            PetSummary(pet: pet)
                        }
                        if gear.sellPrice > 0 {
                            Text("Sells for \(gear.sellPrice) caps").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                if cell.isPetSlot {
                    let pet = player?.pet
                    HStack(spacing: 8) {
                        ActionButton(title: pet?.isSummoned == true || pet?.awaitingFood == true ? "Dismiss" : "Summon",
                                     glyph: glyph, isEnabled: true, action: action)
                        ActionButton(title: "Put away", glyph: nil, isEnabled: true, action: onUnslotPet)
                    }
                } else {
                switch (cell.slot, definition.kind) {
                case (.some, _): ActionButton(title: "Unequip", glyph: glyph, isEnabled: true, action: action)
                case (nil, .equipment): ActionButton(title: "Equip", glyph: glyph, isEnabled: true, action: action)
                case (nil, .consumable): ActionButton(title: "Use", glyph: glyph, isEnabled: true, action: action)
                case (nil, .glider): ActionButton(title: "Fly", glyph: glyph, isEnabled: true, action: action)
                case (nil, .material): EmptyView()
                case (nil, .pet): ActionButton(title: "Summon", glyph: glyph, isEnabled: true, action: action)
                case (nil, .petFood): ActionButton(title: "Feed", glyph: glyph, isEnabled: player?.pet.slot != nil, action: action)
                }
                }
            } else if cell?.isPetSlot == true {
                Text("Pet slot").font(.headline)
                Text("No pet yet. Truffle, the pet keeper in the village, knows a pup looking for a friend.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
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
                    if stats.blockChance > 0 {
                        stat("BLK", StatBonus.percent(stats.blockChance))
                    }
                    if stats.critChance > 0.1 {
                        stat("CRT", StatBonus.percent(stats.critChance))
                    }
                }
            }
        }
        .frame(width: 230, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func stat(_ name: String, _ value: Int) -> some View {
        stat(name, "\(value)")
    }

    private func stat(_ name: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(name).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold).monospacedDigit())
        }
    }
}

/// How full the slotted pet is, and what that means.
private struct PetSummary: View {
    let pet: PetStatus

    var body: some View {
        if let name = pet.slot?.definition.name {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(name)'s belly").font(.caption.weight(.semibold))
                    Spacer()
                    Text(pet.fullness > 0 ? "\(pet.minutesLeft) min" : "Empty")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(pet.fullness))
                    .tint(pet.isHungry || pet.awaitingFood ? .red : .green)
                Text(pet.awaitingFood ? "Starving at home. Feed Kibble to bring \(name) back."
                     : pet.isHungry ? "Hungry: slows down. Feed Kibble soon."
                     : pet.isOut ? "Following you and fetching your drops."
                     : pet.isSummoned ? "Waits while you fly." : "Resting at home.")
                    .font(.caption)
                    .foregroundStyle(pet.isHungry || pet.awaitingFood ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// "Dewleaf Set 2/4" and its bonuses, the unlocked ones lit.
private struct SetSummary: View {
    let set: ItemSet
    let worn: Int

    var body: some View {
        let definition = set.definition
        VStack(alignment: .leading, spacing: 2) {
            Text("\(definition.name) \(worn)/\(definition.pieces.count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Rarity.set.color)
            ForEach(definition.tiers, id: \.pieces) { tier in
                Text("\(tier.pieces) pieces: \(tier.bonus.summary)")
                    .font(.caption2)
                    .foregroundStyle(worn >= tier.pieces ? Rarity.set.color : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                            Text("Buyback").tag(ShopTab.buyback)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 270)
                        if let glyph = session.glyphs?.nextTarget { Image(systemName: glyph) }
                        Spacer()
                        if let caps = session.hud.player?.caps {
                            Label("\(caps)", systemImage: "circle.circle.fill")
                                .foregroundStyle(.yellow)
                                .font(.callout.weight(.semibold).monospacedDigit())
                        }
                    }
                }
                if definition.upgradesGear, let player = session.hud.player {
                    ForgeHeader(session: session, player: player)
                }
                HStack(alignment: .top, spacing: 16) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 6) {
                                if rows.isEmpty {
                                    Text(definition.isShopkeeper
                                         ? session.shopTab == .buyback ? "Nothing to buy back. What you sell waits here for a while, in every shop."
                                         : "Nothing to sell."
                                         : definition.upgradesGear ? "No gear to upgrade."
                                         : definition.makesPetFood ? "Bring me critter drops and I'll bake them into Kibble."
                                         : definition.buysMaterials ? "Bring me whatever the critters drop. Every species has something!"
                                         : "No tasks right now. Come back later!")
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
                            ScrollView {
                                Text(selected.detail)
                                    .font(definition.upgradesGear ? .caption : .callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .scrollIndicators(.hidden)
                            Spacer(minLength: 4)
                            if selected.action != .none {
                                ActionButton(title: actionTitle(selected.action), glyph: session.glyphs?.primary,
                                             isEnabled: selected.isEnabled) {
                                    session.perform(.menu(.confirm))
                                }
                            }
                            if case let .sell(gear, stack) = selected.action, stack > 1 {
                                ActionButton(title: "Sell all ×\(stack) (+\(gear.sellPrice * stack))",
                                             glyph: session.glyphs?.secondary, isEnabled: selected.isEnabled) {
                                    session.perform(.menu(.secondary))
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
        case .buyBack: "Buy back"
        case .upgrade: "Upgrade"
        case .accept: "Accept"
        case .turnIn: "Turn in"
        case .chooseClass: "Choose this path"
        case .makePetFood: "Bake"
        case .trade: "Hand in all"
        case .none: ""
        }
    }
}

/// Materials on hand and the Ward Charm switch (LB/RB, Q/E).
private struct ForgeHeader: View {
    let session: GameSession
    let player: PlayerStatus

    var body: some View {
        HStack(spacing: 14) {
            Label("\(player.inventory.count(of: .amberShard))", systemImage: ItemID.amberShard.symbol)
                .foregroundStyle(ItemID.amberShard.tint)
            Label("\(player.inventory.count(of: .wardCharm))", systemImage: ItemID.wardCharm.symbol)
                .foregroundStyle(ItemID.wardCharm.tint)
            Spacer()
            if let glyph = session.glyphs?.previousTarget { Image(systemName: glyph) }
            Toggle("Ward Charm", isOn: Binding(get: { session.protectUpgrades }, set: { session.setProtectUpgrades($0) }))
                .fixedSize()
            Label("\(player.caps)", systemImage: "circle.circle.fill")
                .foregroundStyle(.yellow)
        }
        .font(.callout.weight(.semibold).monospacedDigit())
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

// MARK: - Character

/// Flyff's character window: the four attributes, points to spend, and what they'd change.
/// Points are picked first (+/−, or left/right) and only spent on Confirm.
struct CharacterPanel: View {
    let session: GameSession

    var body: some View {
        let player = session.hud.player
        let subtitle = player.map { status in
            ["Lv \(status.stats.level)", status.playerClass?.definition.name].compactMap { $0 }.joined(separator: " · ")
        }
        PanelChrome(title: "Character", subtitle: subtitle, glyphs: session.glyphs, onClose: session.closePanel) {
            if let player {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        header(player)
                        ForEach(Array(Attribute.allCases.enumerated()), id: \.element) { index, attribute in
                            AttributeRow(attribute: attribute, value: player.attributes.value(attribute),
                                         pending: session.pendingPoints[attribute],
                                         canAdd: session.pointsLeftToPick > 0,
                                         isSelected: session.selection == index,
                                         onTap: { session.tapSelection(index) },
                                         onStep: { session.adjustPendingPoint(attribute, by: $0) })
                        }
                        HStack(spacing: 10) {
                            ActionButton(title: "Confirm", glyph: session.selection == Attribute.allCases.count ? session.glyphs?.primary : nil,
                                         isEnabled: session.pendingPoints.spent > 0) {
                                session.confirmPendingPoints()
                            }
                            .overlay {
                                Capsule().strokeBorder(session.selection == Attribute.allCases.count ? Color.yellow : .clear, lineWidth: 2)
                            }
                            if session.pendingPoints.spent > 0 {
                                Button("Reset", action: session.clearPendingPoints)
                                    .buttonStyle(.plain)
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    Divider()
                    if let preview = session.previewStats {
                        StatPreview(current: player.stats, preview: preview)
                            .frame(width: 210, alignment: .leading)
                    }
                }
            }
        }
    }

    private func header(_ player: PlayerStatus) -> some View {
        HStack(spacing: 8) {
            let left = session.pointsLeftToPick
            Label(left == 1 ? "1 point to spend" : "\(left) points to spend", systemImage: "plus.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(left > 0 ? .mint : .secondary)
            Spacer()
            if let previous = session.glyphs?.previousTarget, let next = session.glyphs?.nextTarget {
                Image(systemName: previous)
                Text("Bag").font(.caption).foregroundStyle(.secondary)
                Image(systemName: next)
            }
        }
    }
}

private struct AttributeRow: View {
    let attribute: Attribute
    let value: Int
    let pending: Int
    let canAdd: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: attribute.symbol)
                .font(.title3)
                .foregroundStyle(attribute.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(attribute.abbreviation).font(.subheadline.weight(.heavy))
                    Text(attribute.name).font(.caption).foregroundStyle(.secondary)
                }
                Text(attribute.perPoint + " per point").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                Text("\(value)").font(.headline.monospacedDigit())
                if pending > 0 {
                    Text("+\(pending)").font(.headline.monospacedDigit()).foregroundStyle(.mint)
                }
            }
            step("minus", enabled: pending > 0) { onStep(-1) }
            step("plus", enabled: canAdd) { onStep(1) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(isSelected ? 0.35 : 0.15), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? Color.yellow : .clear, lineWidth: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func step(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }
}

/// Each stat now, and what it would become (green) with the picked points spent.
private struct StatPreview: View {
    let current: CombatStats
    let preview: CombatStats

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            line("Attack", "\(current.attack)", "\(preview.attack)")
            line("Defense", "\(current.defense)", "\(preview.defense)")
            line("Max HP", "\(current.maxHP)", "\(preview.maxHP)")
            line("Max MP", "\(current.maxMP)", "\(preview.maxMP)")
            line("Attacks/s", perSecond(current.attackInterval), perSecond(preview.attackInterval))
            line("Critical", StatBonus.percent(current.critChance), StatBonus.percent(preview.critChance))
            line("Skill power", StatBonus.percent(current.skillPower), StatBonus.percent(preview.skillPower))
            if current.blockChance > 0 {
                line("Block", StatBonus.percent(current.blockChance), StatBonus.percent(preview.blockChance))
            }
        }
        .font(.callout)
    }

    private func perSecond(_ interval: Float) -> String {
        String(format: "%.2f", 1 / max(interval, 0.01))
    }

    private func line(_ name: String, _ now: String, _ then: String) -> some View {
        HStack(spacing: 6) {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(now).monospacedDigit()
            if then != now {
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                Text(then).monospacedDigit().foregroundStyle(.green).fontWeight(.semibold)
            }
        }
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
