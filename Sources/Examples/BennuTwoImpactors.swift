import Foundation
import asteroid2026

// Bennu plus two impactors demo, moved from the old package entry point.
// Usage: swift run Examples bennu [output_directory] [steps]
public func run_bennu_two_impactors(output_directory: String, steps: Int) throws {
    var system_rng = SystemRandomNumberGenerator()
    let first_seed = UInt64.random(in: UInt64.min...UInt64.max, using: &system_rng)
    let second_seed = UInt64.random(in: UInt64.min...UInt64.max, using: &system_rng)
    let third_seed = UInt64.random(in: UInt64.min...UInt64.max, using: &system_rng)
    print("asteroid seeds: \(first_seed), \(second_seed), \(third_seed)")
    let simulation = asteroid2026.make_collision(
        first_seed: first_seed, second_seed: second_seed, third_seed: third_seed)
    print("particles: \(simulation.particles.count)")
    try asteroid2026.clear_output_directory(output_directory)
    try simulation.run(steps: steps, output_directory: output_directory, write_every: 10)
    print("done, elapsed: \(simulation.elapsed_time)")
}
