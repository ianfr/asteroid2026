import Foundation

@main
struct asteroid2026 {
    static func main() {
        var system_rng = SystemRandomNumberGenerator()
        let first_seed = UInt64.random(in: UInt64.min...UInt64.max, using: &system_rng)
        let second_seed = UInt64.random(in: UInt64.min...UInt64.max, using: &system_rng)
        let third_seed = UInt64.random(in: UInt64.min...UInt64.max, using: &system_rng)
        print("asteroid seeds: \(first_seed), \(second_seed), \(third_seed)")
        let simulation = make_collision(
            first_seed: first_seed, second_seed: second_seed, third_seed: third_seed)
        print("particles: \(simulation.particles.count)")
        let output_directory = "OUT/desktop"
        do {
            try clear_output_directory(output_directory)
            try simulation.run(steps: 2000, output_directory: output_directory, write_every: 10)
            print("done, elapsed: \(simulation.elapsed_time)")
        }
        catch {
            print("run failed: \(error)")
        }
    }

    static func clear_output_directory(_ path: String) throws {
        let file_manager = FileManager.default
        try file_manager.createDirectory(atPath: path, withIntermediateDirectories: true)
        // A shorter run must not leave frames from a previous, longer run behind.
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        for entry in try file_manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)
        {
            try file_manager.removeItem(at: entry)
        }
    }

    static func make_collision(
        first_seed: UInt64, second_seed: UInt64, third_seed: UInt64
    ) -> simulation_t {
        var config = simulation_config_t()
        config.integrator = .velocity_verlet
        config.adaptive_mode = .mean_velocity
        config.max_timestep = 5.0
        config.cohesion.model = .spring
        let simulation = simulation_t(config: config)
        // Volume-equivalent Bennu sphere; mass and rotation from OSIRIS-REx (2019).
        let bennu_radius = 245.0
        let bennu_mass = 7.329e10
        let rotation_period = 4.296056 * 3600.0
        let bulk_density = bennu_mass / (4.0 / 3.0 * Double.pi * pow(bennu_radius, 3))
        simulation.add_spherical_asteroid(
            total_mass: bennu_mass,
            radius: bennu_radius,
            particle_radius: 11.7,
            center: vector3_t(0, 0, 0),
            velocity: vector3_t(0, 0, 0),
            color: 0,
            packing: .random_pack,
            radius_spread: 2.0,
            seed: first_seed,
            angular_velocity: vector3_t(0, 0, 2.0 * Double.pi / rotation_period))
        // Nearby, oblique approaches leave tens of metres for gravitational acceleration.
        simulation.add_spherical_asteroid(
            total_mass: bulk_density * (4.0 / 3.0 * Double.pi * pow(100.0, 3)),
            radius: 100.0,
            particle_radius: 10.0,
            center: vector3_t(365, 60, 0),
            velocity: vector3_t(-0.12, 0, 0),
            color: 1,
            packing: .random_pack,
            radius_spread: 2.0,
            seed: second_seed)
        simulation.add_spherical_asteroid(
            total_mass: bulk_density * (4.0 / 3.0 * Double.pi * pow(75.0, 3)),
            radius: 75.0,
            particle_radius: 8.0,
            center: vector3_t(-335, -50, 0),
            velocity: vector3_t(0.10, 0, 0),
            color: 2,
            packing: .random_pack,
            radius_spread: 1.5,
            seed: third_seed)
        return simulation
    }
}
