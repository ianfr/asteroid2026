public enum integration_scheme_t: Sendable {
    case euler
    case velocity_verlet
    case runge_kutta4
}

public enum adaptive_step_mode_t: Sendable {
    case fixed
    case max_velocity
    case mean_velocity
}

public struct simulation_config_t: Sendable {
    public var gravitational_constant: Double = 6.67430e-11
    public var softening_length: Double = 1e-3
    public var barnes_hut_theta: Double = 0.5
    public var use_barnes_hut: Bool = true
    public var barnes_hut_threshold: Int = 64
    public var restitution: Double = 0.86
    public var separation_buffer: Double = 0.05
    public var positional_correction: Double = 0.8
    public var collision_iterations: Int = 2
    public var integrator: integration_scheme_t = .velocity_verlet
    public var adaptive_mode: adaptive_step_mode_t = .mean_velocity
    public var max_timestep: Double = 0.15
    public var min_timestep: Double = 1e-5
    public var cohesion: cohesion_config_t = cohesion_config_t()

    public init() {}
}
