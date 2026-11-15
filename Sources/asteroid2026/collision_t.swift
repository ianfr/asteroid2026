import Dispatch
import Foundation

public struct collision_event_t: Sendable {
    public var index_a: Int
    public var index_b: Int
    public var penetration: Double
    public var distance: Double

    public init(index_a: Int, index_b: Int, penetration: Double, distance: Double) {
        self.index_a = index_a
        self.index_b = index_b
        self.penetration = penetration
        self.distance = distance
    }
}

private struct cell_key_t: Hashable, Sendable {
    var ix: Int
    var iy: Int
    var iz: Int
}

private func cell_key_for(_ position: vector3_t, cell_size: Double) -> cell_key_t {
    return cell_key_t(
        ix: Int(floor(position.x / cell_size)),
        iy: Int(floor(position.y / cell_size)),
        iz: Int(floor(position.z / cell_size)))
}

private final class event_slots_t: @unchecked Sendable {
    var slots: [[collision_event_t]]
    init(count: Int) { slots = [[collision_event_t]](repeating: [], count: count) }
}

public func detect_collision_events(
    particles: [particle_t],
    separation_buffer: Double
) -> [collision_event_t] {
    let count = particles.count
    guard count > 1 else { return [] }
    var max_radius = 0.0
    for particle in particles { max_radius = max(max_radius, particle.radius) }
    let cell_size = max(2.0 * max_radius + separation_buffer, 1e-9)
    var building = [cell_key_t: [Int]]()
    building.reserveCapacity(count)
    for i in 0..<count {
        let key = cell_key_for(particles[i].position, cell_size: cell_size)
        building[key, default: []].append(i)
    }
    let grid = building
    let slots = event_slots_t(count: count)
    DispatchQueue.concurrentPerform(iterations: count) { i in
        let base = cell_key_for(particles[i].position, cell_size: cell_size)
        var local = [collision_event_t]()
        for dx in -1...1 {
            for dy in -1...1 {
                for dz in -1...1 {
                    let key = cell_key_t(ix: base.ix + dx, iy: base.iy + dy, iz: base.iz + dz)
                    guard let members = grid[key] else { continue }
                    for j in members where j > i {
                        let offset = particles[j].position - particles[i].position
                        let distance = offset.norm()
                        let contact = particles[i].radius + particles[j].radius + separation_buffer
                        if distance <= contact {
                            local.append(
                                collision_event_t(
                                    index_a: i, index_b: j,
                                    penetration: contact - distance, distance: distance))
                        }
                    }
                }
            }
        }
        slots.slots[i] = local
    }
    var seen = Set<Int64>()
    var events = [collision_event_t]()
    for slot in slots.slots {
        for event in slot {
            let low = Int64(min(event.index_a, event.index_b))
            let high = Int64(max(event.index_a, event.index_b))
            let key = (low << 32) | high
            if seen.insert(key).inserted {
                events.append(event)
            }
        }
    }
    events.sort { $0.penetration > $1.penetration }
    return events
}

public func group_independent_batches(
    events: [collision_event_t]
) -> [[collision_event_t]] {
    var batches = [[collision_event_t]]()
    var used_per_batch = [Set<Int>]()
    for event in events {
        var placed = false
        for b in batches.indices {
            if !used_per_batch[b].contains(event.index_a)
                && !used_per_batch[b].contains(event.index_b)
            {
                batches[b].append(event)
                used_per_batch[b].insert(event.index_a)
                used_per_batch[b].insert(event.index_b)
                placed = true
                break
            }
        }
        if !placed {
            batches.append([event])
            used_per_batch.append(Set([event.index_a, event.index_b]))
        }
    }
    return batches
}

private struct impulse_delta_t {
    var index: Int
    var delta_velocity: vector3_t
    var delta_position: vector3_t
}

public func resolve_collision_events(
    particles: inout [particle_t],
    events: [collision_event_t],
    restitution: Double,
    positional_correction: Double
) {
    let batches = group_independent_batches(events: events)
    for batch in batches {
        var deltas = [impulse_delta_t]()
        deltas.reserveCapacity(batch.count * 2)
        for event in batch {
            let i = event.index_a
            let j = event.index_b
            guard i < particles.count, j < particles.count else { continue }
            let offset = particles[j].position - particles[i].position
            let distance = offset.norm()
            guard distance > 1e-12 else { continue }
            let normal = offset / distance
            let relative = particles[i].velocity - particles[j].velocity
            let closing = relative.dot(normal)
            if closing <= 0 { continue }
            let mass_a = particles[i].mass
            let mass_b = particles[j].mass
            let reduced = 1.0 / (1.0 / mass_a + 1.0 / mass_b)
            let impulse = (1.0 + restitution) * reduced * closing
            let correction = normal * (event.penetration * positional_correction)
            let weight_a = (1.0 / mass_a) / (1.0 / mass_a + 1.0 / mass_b)
            let weight_b = (1.0 / mass_b) / (1.0 / mass_a + 1.0 / mass_b)
            deltas.append(
                impulse_delta_t(
                    index: i, delta_velocity: normal * (-impulse / mass_a),
                    delta_position: correction * (-weight_a)))
            deltas.append(
                impulse_delta_t(
                    index: j, delta_velocity: normal * (impulse / mass_b),
                    delta_position: correction * weight_b))
        }
        for delta in deltas {
            particles[delta.index].velocity += delta.delta_velocity
            particles[delta.index].position += delta.delta_position
        }
    }
}

public func handle_collisions(
    particles: inout [particle_t],
    config: simulation_config_t
) {
    for _ in 0..<max(config.collision_iterations, 1) {
        let events = detect_collision_events(
            particles: particles, separation_buffer: config.separation_buffer)
        if events.isEmpty { break }
        resolve_collision_events(
            particles: &particles, events: events,
            restitution: config.restitution,
            positional_correction: config.positional_correction)
    }
}

public func next_timestep_max(
    particles: [particle_t], upper_bound: Double, lower_bound: Double
) -> Double {
    guard particles.count >= 2 else { return upper_bound }
    var top = 0.0
    var second = 0.0
    var radius_sum = 0.0
    for particle in particles {
        let speed = particle.velocity.norm()
        radius_sum += particle.radius
        if speed > top {
            second = top
            top = speed
        }
        else if speed > second {
            second = speed
        }
    }
    let mean_radius = radius_sum / Double(particles.count)
    guard top + second > 0 else { return upper_bound }
    let raw = (2.0 * mean_radius) / (top + second)
    return min(max(raw, lower_bound), upper_bound)
}

public func next_timestep_mean(
    particles: [particle_t], upper_bound: Double, lower_bound: Double
) -> Double {
    guard !particles.isEmpty else { return upper_bound }
    var speed_sum = 0.0
    var radius_sum = 0.0
    for particle in particles {
        speed_sum += particle.velocity.norm()
        radius_sum += particle.radius
    }
    let mean_speed = speed_sum / Double(particles.count)
    let mean_radius = radius_sum / Double(particles.count)
    guard mean_speed > 1e-12 else { return upper_bound }
    let raw = (mean_radius / mean_speed) - 1e-9
    return min(max(raw, lower_bound), upper_bound)
}
