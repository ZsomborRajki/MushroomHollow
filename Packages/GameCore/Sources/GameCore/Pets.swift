/// Flyff-style pickup pets: a passive companion that trots after its owner and fetches the
/// owner's ground drops. It never fights. Pets sit in the pet slot, eat Kibble (baked from mob
/// materials by a pet keeper), and slow down when hungry; a starving pet goes home until fed.
public enum PetKind: String, Codable, CodingKeyRepresentable, Sendable, CaseIterable {
    /// Pip, a pocket-sized pup.
    case pup

    /// The item that holds this pet.
    public var item: ItemID {
        switch self {
        case .pup: .pip
        }
    }

    /// Collision radius on the ground plane, in meters.
    public var radius: Float {
        switch self {
        case .pup: 0.22
        }
    }
}

/// Why a pet left the world (it still sits in the pet slot unless unslotted).
public enum PetDismissal: String, Codable, Sendable {
    /// Its owner sent it home.
    case requested
    /// It ran out of food; it comes back by itself once fed.
    case starving
    /// Taken out of the pet slot.
    case unslotted
}

/// What a client needs to render one pet.
public struct PetSnapshot: Codable, Sendable, Equatable, Identifiable {
    /// Every player has at most one pet out, so the owner doubles as the pet's ID.
    public let owner: EntityID
    public let kind: PetKind
    /// y is height above the ground (always 0: pets walk).
    public let position: Vec3
    public let yaw: Float
    public let isMoving: Bool
    public let isHungry: Bool
    public let isFetching: Bool

    public var id: EntityID { owner }
}

/// The owner's private view of their pet slot.
public struct PetStatus: Codable, Sendable, Equatable {
    /// The pet item in the pet slot.
    public let slot: ItemID?
    /// 0...1.
    public let fullness: Float
    /// Minutes of following left on the current belly.
    public let minutesLeft: Int
    public let isHungry: Bool
    /// Called out (it may still be tucked away while you fly or have fainted).
    public let isSummoned: Bool
    /// Following you in the world right now.
    public let isOut: Bool
    /// Starved and went home; feeding brings it back.
    public let awaitingFood: Bool

    public var kind: PetKind? {
        if case let .pet(kind) = slot?.definition.kind { return kind }
        return nil
    }
}

/// Saved pet state.
public struct PetProfile: Codable, Sendable, Equatable {
    public var slot: ItemID?
    /// Food left per pet, in ticks of following; missing = full.
    public var fullness: [PetKind: Int]
    public var summoned: Bool
    public var awaitingFood: Bool

    public init(slot: ItemID? = nil, fullness: [PetKind: Int] = [:], summoned: Bool = false, awaitingFood: Bool = false) {
        self.slot = slot
        self.fullness = fullness
        self.summoned = summoned
        self.awaitingFood = awaitingFood
    }
}

struct PetData: Codable, Sendable {
    var slot: ItemID?
    var fullness: [PetKind: Int] = [:]
    var summoned = false
    var awaitingFood = false
    /// Present while the pet is out in the world.
    var body: PetBody?

    var kind: PetKind? {
        if case let .pet(kind) = slot?.definition.kind { return kind }
        return nil
    }

    func fullness(of kind: PetKind) -> Int { fullness[kind] ?? GameSimulation.petMaxFullness }

    init(profile: PetProfile? = nil) {
        guard let profile else { return }
        slot = profile.slot
        fullness = profile.fullness
        summoned = profile.summoned
        awaitingFood = profile.awaitingFood
    }

    var profile: PetProfile {
        PetProfile(slot: slot, fullness: fullness, summoned: summoned, awaitingFood: awaitingFood)
    }
}

struct PetBody: Codable, Sendable {
    var position: Vec2
    var yaw: Float
    var velocity: Vec2 = .zero
    /// The ground drop it's running to.
    var fetching: UInt32?
}

extension ItemID {
    /// Kibble a pet keeper bakes from one of these: mob materials only (amber and charms are for the forge).
    public var kibbleValue: Int? {
        guard case .material = definition.kind, self != .amberShard, self != .wardCharm else { return nil }
        return 1 + definition.sellPrice * 2 / 5
    }
}

extension GameSimulation {
    // Hunger, in ticks of following: a full belly lasts 30 minutes, one Kibble 3.
    public static let petMaxFullness = ticks(30 * 60)
    public static let kibbleFullness = ticks(3 * 60)
    /// At or below this, the pet is hungry and slows down.
    public static let petHungryFullness = petMaxFullness / 4
    static let hungryPetSpeedFactor: Float = 0.55

    static let petSpeed: Float = 5.5
    /// Hurrying back when it has fallen behind.
    static let petCatchUpSpeed: Float = 7.5
    static let petCatchUpDistance: Float = 6
    /// Farther than this (a respawn, a teleport, a long flight), it simply pops up beside you.
    static let petTeleportDistance: Float = 25
    static let petTurnRate: Float = 12
    /// It goes after drops this close to its owner...
    static let petFetchRadius: Float = 7
    /// ...and gives up on one that ends up this far from them.
    static let petFetchLeash: Float = 12
    /// How close it gets to a drop to pick it up.
    static let petReach: Float = 0.6

    // MARK: - Commands

    mutating func slotPet(_ item: ItemID, player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player else { return .notAvailable }
        guard case .pet = item.definition.kind else { return .notUsable }
        guard data.inventory.remove(item, count: 1) else { return .missingItem }
        if let previous = data.pet.slot {
            data.inventory.add(previous, count: 1) // the slot we just freed makes room
        }
        data.pet.slot = item
        data.pet.body = nil
        data.pet.awaitingFood = false
        player.player = data
        events.append(.equipmentChanged(player: player.id))
        return nil
    }

    mutating func unslotPet(player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player, let item = data.pet.slot else { return .noPet }
        guard data.inventory.add(item, count: 1) == 0 else { return .inventoryFull }
        let wasSummoned = data.pet.summoned
        data.pet.slot = nil
        data.pet.summoned = false
        data.pet.awaitingFood = false
        data.pet.body = nil
        player.player = data
        if wasSummoned { events.append(.petDismissed(player: player.id, reason: .unslotted)) }
        events.append(.equipmentChanged(player: player.id))
        return nil
    }

    mutating func summonPet(player: inout WorldEntity) -> ActionFailure? {
        guard player.stats.isAlive, var data = player.player else { return .notUsable }
        guard let kind = data.pet.kind else { return .noPet }
        guard data.pet.fullness(of: kind) > 0 else { return .petHungry }
        guard !data.pet.summoned else { return nil }
        data.pet.summoned = true
        data.pet.awaitingFood = false
        player.player = data
        events.append(.petSummoned(player: player.id))
        return nil
    }

    mutating func dismissPet(player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player else { return .notAvailable }
        guard data.pet.kind != nil else { return .noPet }
        guard data.pet.summoned || data.pet.awaitingFood else { return nil }
        let wasSummoned = data.pet.summoned
        data.pet.summoned = false
        data.pet.awaitingFood = false
        data.pet.body = nil
        player.player = data
        if wasSummoned { events.append(.petDismissed(player: player.id, reason: .requested)) }
        return nil
    }

    /// Kibble fills the slotted pet right up (using only as much as it needs). A pet that
    /// went home starving comes straight back.
    mutating func feedPet(player: inout WorldEntity) -> ActionFailure? {
        guard player.stats.isAlive, var data = player.player else { return .notUsable }
        guard let kind = data.pet.kind else { return .noPet }
        let fullness = data.pet.fullness(of: kind)
        let have = data.inventory.count(of: .kibble)
        guard have > 0 else { return .missingItem }
        guard fullness < Self.petMaxFullness else { return .petFull }

        let needed = (Self.petMaxFullness - fullness + Self.kibbleFullness - 1) / Self.kibbleFullness
        let eaten = min(needed, have)
        data.inventory.remove(.kibble, count: eaten)
        data.pet.fullness[kind] = min(Self.petMaxFullness, fullness + eaten * Self.kibbleFullness)
        events.append(.petFed(player: player.id, kibble: eaten))
        if data.pet.awaitingFood {
            data.pet.awaitingFood = false
            data.pet.summoned = true
            events.append(.petSummoned(player: player.id))
        }
        player.player = data
        return nil
    }

    /// At a pet keeper: bakes `count` of a mob material into Kibble, all or nothing.
    mutating func makePetFood(_ item: ItemID, count: Int, at npc: NPCID, player: inout WorldEntity) -> ActionFailure? {
        guard var data = player.player, count > 0 else { return .notAvailable }
        guard isNear(npc, player) else { return .tooFar }
        guard npc.definition.makesPetFood else { return .notAvailable }
        guard let value = item.kibbleValue else { return .notUsable }
        var bag = data.inventory
        guard bag.remove(item, count: count) else { return .missingItem }
        let kibble = count * value
        guard bag.add(.kibble, count: kibble) == 0 else { return .inventoryFull }
        data.inventory = bag
        player.player = data
        events.append(.itemReceived(player: player.id, item: .kibble, count: kibble))
        reportCollectProgress(for: &player)
        return nil
    }

    // MARK: - Simulation

    /// Moves every pet that's out, in owner-ID order (deterministic).
    mutating func stepPets() {
        for id in order {
            guard var owner = entities[id], var pet = owner.player?.pet, pet.summoned || pet.body != nil else { continue }
            stepPet(&pet, owner: &owner)
            owner.player?.pet = pet
            entities[id] = owner
        }
    }

    private mutating func stepPet(_ pet: inout PetData, owner: inout WorldEntity) {
        // Tucked away while dismissed, while its owner flies (or glides down), and while they're fainted.
        guard pet.summoned, let kind = pet.kind, owner.stats.isAlive, !isAirborne(owner) else {
            pet.body = nil
            return
        }
        let dt = Self.tickDuration
        let spot = petFollowSpot(owner, radius: kind.radius)
        var body = pet.body ?? PetBody(position: spot, yaw: owner.yaw)

        // Hunger only drains while it's out.
        let fullness = pet.fullness(of: kind) - 1
        pet.fullness[kind] = max(0, fullness)
        if fullness == Self.petHungryFullness { events.append(.petHungry(player: owner.id)) }
        guard fullness > 0 else {
            pet.summoned = false
            pet.awaitingFood = true
            pet.body = nil
            events.append(.petDismissed(player: owner.id, reason: .starving))
            return
        }

        if body.position.distance(to: owner.position.xz) > Self.petTeleportDistance {
            body = PetBody(position: spot, yaw: owner.yaw)
        }

        // Fetch the nearest of its owner's drops, else trot along behind them.
        if let id = body.fetching, !canFetch(id, for: owner, within: Self.petFetchLeash) { body.fetching = nil }
        if body.fetching == nil { body.fetching = nearestFetchable(to: body.position, for: owner) }
        let fetchTarget = body.fetching.flatMap { id in drops.first { $0.id == id }?.position }
        let goal = fetchTarget ?? spot
        let offset = goal - body.position
        let distance = offset.length

        // A little slack before setting off, so it doesn't shuffle at every step you take.
        let wasMoving = body.velocity.length > 0.05
        let shouldMove = fetchTarget != nil ? distance > Self.petReach * 0.5 : distance > (wasMoving ? 0.3 : 1.0)
        let hungry = fullness <= Self.petHungryFullness
        var speed = distance > Self.petCatchUpDistance ? Self.petCatchUpSpeed : Self.petSpeed
        if hungry { speed *= Self.hungryPetSpeedFactor }
        if fetchTarget == nil { speed = min(speed, distance * 4) } // ease in to its spot

        if shouldMove, distance > 1e-4 {
            let direction = offset / distance
            let step = min(distance, speed * dt)
            let start = body.position
            body.position = map.resolve(start + direction * step, radius: kind.radius)
            body.velocity = (body.position - start) / dt
            body.yaw = AngleMath.moveToward(body.yaw, AngleMath.yaw(facing: direction), maxDelta: Self.petTurnRate * dt)
        } else {
            body.velocity = .zero
            let toOwner = owner.position.xz - body.position
            if toOwner.length > 0.3 {
                body.yaw = AngleMath.moveToward(body.yaw, AngleMath.yaw(facing: toOwner), maxDelta: Self.petTurnRate * 0.5 * dt)
            }
        }

        if let id = body.fetching, let target = fetchTarget, body.position.distance(to: target) <= Self.petReach {
            body.fetching = nil
            if let index = drops.firstIndex(where: { $0.id == id }), grantDrop(at: index, to: &owner) == nil {
                events.append(.petFetched(player: owner.id))
            }
        }
        pet.body = body
    }

    /// Behind its owner and a little to the side.
    private func petFollowSpot(_ owner: WorldEntity, radius: Float) -> Vec2 {
        let forward = AngleMath.direction(forYaw: owner.yaw)
        let side = Vec2(forward.y, -forward.x)
        return map.resolve(owner.position.xz - forward * 1.2 + side * 0.7, radius: radius)
    }

    /// The owner's own drop, ready to collect, close enough to them, and with room in their bag.
    private func canFetch(_ id: UInt32, for owner: WorldEntity, within range: Float) -> Bool {
        guard let drop = drops.first(where: { $0.id == id }) else { return false }
        return canFetch(drop, for: owner, within: range)
    }

    private func canFetch(_ drop: GroundDrop, for owner: WorldEntity, within range: Float) -> Bool {
        guard drop.owner == owner.id, tick >= drop.availableAtTick,
              drop.position.distance(to: owner.position.xz) <= range else { return false }
        switch drop.kind {
        case .caps: return true
        case let .item(item, _): return owner.player?.inventory.canAdd(item, count: 1) ?? false
        }
    }

    private func nearestFetchable(to position: Vec2, for owner: WorldEntity) -> UInt32? {
        var best: (id: UInt32, distance: Float)?
        for drop in drops where canFetch(drop, for: owner, within: Self.petFetchRadius) {
            let distance = drop.position.distance(to: position)
            if best == nil || distance < best!.distance { best = (drop.id, distance) }
        }
        return best?.id
    }

    // MARK: - Views

    var petSnapshots: [PetSnapshot] {
        order.compactMap { id in
            guard let owner = entities[id], let pet = owner.player?.pet, let kind = pet.kind, let body = pet.body else { return nil }
            return PetSnapshot(owner: id, kind: kind, position: Vec3(body.position.x, 0, body.position.y), yaw: body.yaw,
                               isMoving: body.velocity.length > 0.05,
                               isHungry: pet.fullness(of: kind) <= Self.petHungryFullness,
                               isFetching: body.fetching != nil)
        }
    }

    func petStatus(_ pet: PetData) -> PetStatus {
        let fullness = pet.kind.map(pet.fullness(of:)) ?? 0
        return PetStatus(
            slot: pet.slot,
            fullness: Float(fullness) / Float(Self.petMaxFullness),
            minutesLeft: (fullness + Self.tickRate * 60 - 1) / (Self.tickRate * 60),
            isHungry: pet.kind != nil && fullness <= Self.petHungryFullness,
            isSummoned: pet.summoned,
            isOut: pet.body != nil,
            awaitingFood: pet.awaitingFood)
    }
}
