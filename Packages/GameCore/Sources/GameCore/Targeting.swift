/// Client-side target picking (tab-targeting). Pure functions over a snapshot, so
/// they work the same offline and online.
extension WorldSnapshot {
    public static let targetingRange: Float = 18

    /// Living mobs within `range` of `position`, nearest first.
    public func hostiles(near position: Vec3, within range: Float = targetingRange) -> [EntitySnapshot] {
        entities
            .filter { $0.kind.isMob && $0.isAlive && $0.position.xz.distance(to: position.xz) <= range }
            .sorted {
                let a = $0.position.xz.distance(to: position.xz), b = $1.position.xz.distance(to: position.xz)
                return a == b ? $0.id < $1.id : a < b
            }
    }

    /// Auto-targeting never picks a fight with a Giant by accident (unless it's already after you);
    /// cycling targets still reaches them.
    public func nearestHostile(to position: Vec3, within range: Float = targetingRange) -> EntityID? {
        hostiles(near: position, within: range).first { !$0.isGiant || ($0.target != nil && $0.target == viewer?.id) }?.id
    }

    /// Steps through hostiles by distance; wraps around. With no current target, picks the nearest.
    public func cycleTarget(from position: Vec3, current: EntityID?, step: Int, within range: Float = targetingRange) -> EntityID? {
        let candidates = hostiles(near: position, within: range)
        guard !candidates.isEmpty else { return nil }
        guard let current, let index = candidates.firstIndex(where: { $0.id == current }) else {
            return candidates[0].id
        }
        let count = candidates.count
        return candidates[((index + step) % count + count) % count].id
    }
}
