import Dispatch
import Foundation

private final class acceleration_box_t: @unchecked Sendable {
    var values: [vector3_t]
    init(count: Int) { values = [vector3_t](repeating: vector3_t(), count: count) }
}

public func compute_accelerations_brute(
    particles: [particle_t],
    gravitational_constant: Double,
    softening_length: Double
) -> [vector3_t] {
    let count = particles.count
    guard count > 0 else { return [] }
    let box = acceleration_box_t(count: count)
    let softening_squared = softening_length * softening_length
    DispatchQueue.concurrentPerform(iterations: count) { i in
        var total = vector3_t()
        for j in 0..<count where j != i {
            let offset = particles[j].position - particles[i].position
            let dist_squared = offset.norm_squared() + softening_squared
            guard dist_squared > 0 else { continue }
            let dist = dist_squared.squareRoot()
            total += offset * (gravitational_constant * particles[j].mass / (dist_squared * dist))
        }
        box.values[i] = total
    }
    return box.values
}

public func compute_accelerations(
    particles: [particle_t],
    config: simulation_config_t
) -> [vector3_t] {
    let count = particles.count
    guard count > 0 else { return [] }
    if !config.use_barnes_hut || count < config.barnes_hut_threshold {
        return compute_accelerations_brute(
            particles: particles,
            gravitational_constant: config.gravitational_constant,
            softening_length: config.softening_length)
    }
    let masses = particles.map { $0.mass }
    let positions = particles.map { $0.position }
    guard let root = build_octree(particles: particles, masses: masses, positions: positions) else {
        return [vector3_t](repeating: vector3_t(), count: count)
    }
    let box = acceleration_box_t(count: count)
    let softening_squared = config.softening_length * config.softening_length
    DispatchQueue.concurrentPerform(iterations: count) { i in
        box.values[i] = root.acceleration_on(
            target_index: i, target_position: positions[i],
            theta: config.barnes_hut_theta,
            softening_squared: softening_squared,
            gravitational_constant: config.gravitational_constant)
    }
    return box.values
}
