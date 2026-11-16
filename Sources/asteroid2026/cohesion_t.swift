import Dispatch
import Foundation

public enum cohesion_model_t: Sendable {
    case none
    case spring
}

public struct cohesion_config_t: Sendable {
    public var model: cohesion_model_t = .none
    public var spring_stiffness: Double = 100.0
    public var spring_damping: Double = 1e4
    public var connect_factor: Double = 1.2
    public var connect_momentum: Double = 1e7
    public var break_momentum: Double = 3e7

    public init() {}
}

public func calibrated_cohesion_config(
    particle_mass: Double,
    particle_radius: Double,
    surface_gravity: Double,
    hold_speed: Double,
    break_speed: Double,
    overlap_fraction: Double
) -> cohesion_config_t {
    var config = cohesion_config_t()
    config.model = .spring
    let reduced = particle_mass / 2.0
    // Bonds form below the hold speed and break above the break speed.
    config.connect_momentum = reduced * hold_speed
    config.break_momentum = reduced * break_speed
    // Stiffness carries one particle weight at the allowed overlap.
    config.spring_stiffness =
        particle_mass * surface_gravity / (overlap_fraction * particle_radius)
    // Near-critical damping of the reduced two-body oscillator.
    config.spring_damping = 2.0 * (config.spring_stiffness * reduced).squareRoot()
    return config
}

public struct bond_t: Hashable, Sendable {
    public var index_a: Int
    public var index_b: Int
    public var rest_length: Double

    public init(index_a: Int, index_b: Int, rest_length: Double) {
        self.index_a = index_a
        self.index_b = index_b
        self.rest_length = rest_length
    }
}

public struct cohesion_state_t: Sendable {
    public var bonds: Set<bond_t> = []

    public init() {}
}

private struct cohesion_cell_key_t: Hashable, Sendable {
    var ix: Int
    var iy: Int
    var iz: Int
}

private func cohesion_cell_key_for(_ position: vector3_t, cell_size: Double) -> cohesion_cell_key_t
{
    return cohesion_cell_key_t(
        ix: Int(floor(position.x / cell_size)),
        iy: Int(floor(position.y / cell_size)),
        iz: Int(floor(position.z / cell_size)))
}

private final class cohesion_pair_slots_t: @unchecked Sendable {
    var slots: [[(Int, Int)]]
    init(count: Int) { slots = [[(Int, Int)]](repeating: [], count: count) }
}

public func relative_momentum(
    first: particle_t, second: particle_t
) -> Double {
    let reduced = 1.0 / (1.0 / first.mass + 1.0 / second.mass)
    return reduced * (first.velocity - second.velocity).norm()
}

private func nearby_pairs(
    particles: [particle_t], reach_factor: Double
) -> [(Int, Int)] {
    let count = particles.count
    guard count > 1 else { return [] }
    var max_radius = 0.0
    for particle in particles { max_radius = max(max_radius, particle.radius) }
    let cell_size = max(2.0 * max_radius * reach_factor, 1e-9)
    var building = [cohesion_cell_key_t: [Int]]()
    building.reserveCapacity(count)
    for i in 0..<count {
        let key = cohesion_cell_key_for(particles[i].position, cell_size: cell_size)
        building[key, default: []].append(i)
    }
    let grid = building
    let slots = cohesion_pair_slots_t(count: count)
    DispatchQueue.concurrentPerform(iterations: count) { i in
        let base = cohesion_cell_key_for(particles[i].position, cell_size: cell_size)
        var local = [(Int, Int)]()
        for dx in -1...1 {
            for dy in -1...1 {
                for dz in -1...1 {
                    let key = cohesion_cell_key_t(
                        ix: base.ix + dx, iy: base.iy + dy, iz: base.iz + dz)
                    guard let members = grid[key] else { continue }
                    for j in members where j > i {
                        let reach = (particles[i].radius + particles[j].radius) * reach_factor
                        let gap = (particles[j].position - particles[i].position).norm()
                        if gap <= reach {
                            local.append((i, j))
                        }
                    }
                }
            }
        }
        slots.slots[i] = local
    }
    var seen = Set<Int64>()
    var pairs = [(Int, Int)]()
    for slot in slots.slots {
        for (a, b) in slot {
            let key = (Int64(a) << 32) | Int64(b)
            if seen.insert(key).inserted {
                pairs.append((a, b))
            }
        }
    }
    return pairs
}

public func update_cohesion_bonds(
    particles: [particle_t],
    state: inout cohesion_state_t,
    config: cohesion_config_t
) {
    guard config.model == .spring else {
        state.bonds.removeAll()
        return
    }
    // break threshold never sits below the connect threshold
    let break_limit = max(config.break_momentum, config.connect_momentum)
    var survivors = Set<bond_t>()
    for bond in state.bonds {
        guard bond.index_a < particles.count, bond.index_b < particles.count else { continue }
        if relative_momentum(first: particles[bond.index_a], second: particles[bond.index_b])
            <= break_limit
        {
            survivors.insert(bond)
        }
    }
    for (a, b) in nearby_pairs(particles: particles, reach_factor: config.connect_factor) {
        if survivors.contains(where: { $0.index_a == a && $0.index_b == b }) { continue }
        if relative_momentum(first: particles[a], second: particles[b]) < config.connect_momentum {
            survivors.insert(
                bond_t(
                    index_a: a, index_b: b,
                    rest_length: particles[a].radius + particles[b].radius))
        }
    }
    state.bonds = survivors
}

private final class cohesion_delta_box_t: @unchecked Sendable {
    var values: [vector3_t]
    init(count: Int) { values = [vector3_t](repeating: vector3_t(), count: count) }
}

public func cohesion_accelerations(
    particles: [particle_t],
    bonds: Set<bond_t>,
    config: cohesion_config_t
) -> [vector3_t] {
    let count = particles.count
    guard config.model == .spring, count > 0, !bonds.isEmpty else {
        return [vector3_t](repeating: vector3_t(), count: count)
    }
    let list = Array(bonds)
    let force_box = cohesion_delta_box_t(count: list.count)
    DispatchQueue.concurrentPerform(iterations: list.count) { k in
        let bond = list[k]
        guard bond.index_a < count, bond.index_b < count else { return }
        let first = particles[bond.index_a]
        let second = particles[bond.index_b]
        let offset = second.position - first.position
        let distance = offset.norm()
        guard distance > 1e-12 else { return }
        let normal = offset / distance
        let stretch = distance - bond.rest_length
        let closing = (second.velocity - first.velocity).dot(normal)
        // pull stretched bonds together, damp separation along the bond
        let magnitude = config.spring_stiffness * stretch + config.spring_damping * closing
        force_box.values[k] = normal * magnitude
    }
    var result = [vector3_t](repeating: vector3_t(), count: count)
    for k in list.indices {
        let bond = list[k]
        guard bond.index_a < count, bond.index_b < count else { continue }
        let force = force_box.values[k]
        result[bond.index_a] += force / particles[bond.index_a].mass
        result[bond.index_b] -= force / particles[bond.index_b].mass
    }
    return result
}
