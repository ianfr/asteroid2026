import Foundation

public final class simulation_t {
    public var particles: [particle_t]
    public var config: simulation_config_t
    public var elapsed_time: Double = 0
    public var step_count: Int = 0
    public var cohesion_bond_count: Int { cohesion_state.bonds.count }
    private var cached_accelerations: [vector3_t]
    private var cohesion_state = cohesion_state_t()

    public init(particles: [particle_t] = [], config: simulation_config_t = simulation_config_t()) {
        self.particles = particles
        self.config = config
        self.cached_accelerations = compute_accelerations(particles: particles, config: config)
    }

    public func add_asteroid(_ newcomers: [particle_t]) {
        particles.append(contentsOf: newcomers)
        reassign_ids(particles: &particles)
        cached_accelerations = compute_accelerations(particles: particles, config: config)
    }

    public func add_spherical_asteroid(
        total_mass: Double, radius: Double, particle_radius: Double,
        center: vector3_t, velocity: vector3_t, color: Int,
        packing: packing_t = .grid, radius_spread: Double = 0,
        volume_fraction: Double = 0.55, seed: UInt64 = 0,
        angular_velocity: vector3_t = vector3_t()
    ) {
        let next_id = particles.count
        let asteroid_id = (particles.map { $0.asteroid_id }.max() ?? -1) + 1
        let newcomers = make_spherical_asteroid(
            total_mass: total_mass, radius: radius, particle_radius: particle_radius,
            center: center, velocity: velocity,
            asteroid_id: asteroid_id, color: color, start_id: next_id,
            packing: packing, radius_spread: radius_spread,
            volume_fraction: volume_fraction, seed: seed, angular_velocity: angular_velocity)
        add_asteroid(newcomers)
    }

    public func add_ellipsoid_asteroid(
        total_mass: Double, semi_axes: vector3_t, particle_radius: Double,
        center: vector3_t, velocity: vector3_t, color: Int,
        packing: packing_t = .grid, radius_spread: Double = 0,
        volume_fraction: Double = 0.55, seed: UInt64 = 0,
        angular_velocity: vector3_t = vector3_t()
    ) {
        let next_id = particles.count
        let asteroid_id = (particles.map { $0.asteroid_id }.max() ?? -1) + 1
        let newcomers = make_ellipsoid_asteroid(
            total_mass: total_mass, semi_axes: semi_axes, particle_radius: particle_radius,
            center: center, velocity: velocity,
            asteroid_id: asteroid_id, color: color, start_id: next_id,
            packing: packing, radius_spread: radius_spread,
            volume_fraction: volume_fraction, seed: seed, angular_velocity: angular_velocity)
        add_asteroid(newcomers)
    }

    public func current_timestep() -> Double {
        switch config.adaptive_mode {
        case .fixed:
            return config.max_timestep
        case .max_velocity:
            return next_timestep_max(
                particles: particles,
                upper_bound: config.max_timestep, lower_bound: config.min_timestep)
        case .mean_velocity:
            return next_timestep_mean(
                particles: particles,
                upper_bound: config.max_timestep, lower_bound: config.min_timestep)
        }
    }

    public func combined_accelerations(particles: [particle_t]) -> [vector3_t] {
        let gravity = compute_accelerations(particles: particles, config: config)
        let spring = cohesion_accelerations(
            particles: particles, bonds: cohesion_state.bonds, config: config.cohesion)
        guard spring.count == gravity.count else { return gravity }
        return zip(gravity, spring).map { $0 + $1 }
    }

    public func advance(timestep: Double) {
        guard !particles.isEmpty else { return }
        update_cohesion_bonds(
            particles: particles, state: &cohesion_state, config: config.cohesion)
        cached_accelerations = combined_accelerations(particles: particles)
        cached_accelerations = integrate_step(
            particles: &particles, timestep: timestep, config: config,
            acceleration_fn: combined_accelerations,
            cached_accelerations: cached_accelerations)
        handle_collisions(particles: &particles, config: config)
        elapsed_time += timestep
        step_count += 1
    }

    public func run(steps: Int, output_directory: String? = nil, write_every: Int = 0) throws {
        if let directory = output_directory {
            try FileManager.default.createDirectory(
                atPath: directory, withIntermediateDirectories: true)
            try write_particles_csv(
                particles: particles, path: paraview_frame_path(directory: directory, frame: 0))
        }
        var frame = 1
        for _ in 0..<steps {
            advance(timestep: current_timestep())
            if let directory = output_directory, write_every > 0,
                step_count % write_every == 0
            {
                try write_particles_csv(
                    particles: particles,
                    path: paraview_frame_path(directory: directory, frame: frame))
                frame += 1
            }
        }
    }
}
