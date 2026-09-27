public final class HashTable {
    public enum Kind {
        case eqv
        case equal
    }

    public let kind: Kind
    private var slots: [(key: Value, value: Value)?] = []
    private var buckets: [Int: [Int]] = [:]
    public private(set) var count = 0

    public init(kind: Kind) {
        self.kind = kind
    }

    private func hash(_ key: Value) -> Int {
        schemeHash(key, structural: kind == .equal)
    }

    private func matches(_ a: Value, _ b: Value) -> Bool {
        kind == .equal ? equalValues(a, b) : eqv(a, b)
    }

    private func slotIndex(_ key: Value, _ keyHash: Int) -> Int? {
        buckets[keyHash]?.first { index in
            guard let slot = slots[index] else { return false }
            return matches(slot.key, key)
        }
    }

    public func lookup(_ key: Value) -> Value? {
        guard let index = slotIndex(key, hash(key)) else { return nil }
        return slots[index]?.value
    }

    public func insert(_ key: Value, _ value: Value) {
        let keyHash = hash(key)
        if let index = slotIndex(key, keyHash) {
            slots[index] = (key, value)
            return
        }
        slots.append((key, value))
        buckets[keyHash, default: []].append(slots.count - 1)
        count += 1
    }

    @discardableResult
    public func remove(_ key: Value) -> Bool {
        let keyHash = hash(key)
        guard let index = slotIndex(key, keyHash) else { return false }
        slots[index] = nil
        buckets[keyHash]?.removeAll { $0 == index }
        if buckets[keyHash]?.isEmpty == true { buckets[keyHash] = nil }
        count -= 1
        if slots.count > 32 && count * 2 < slots.count { compact() }
        return true
    }

    public func clear() {
        slots.removeAll()
        buckets.removeAll()
        count = 0
    }

    public var entries: [(key: Value, value: Value)] {
        slots.compactMap { $0 }
    }

    public func copy() -> HashTable {
        let table = HashTable(kind: kind)
        for entry in entries { table.insert(entry.key, entry.value) }
        return table
    }

    private func compact() {
        let live = entries
        clear()
        for entry in live { insert(entry.key, entry.value) }
    }
}
