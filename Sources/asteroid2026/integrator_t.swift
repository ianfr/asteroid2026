public typealias acceleration_fn_t = ([particle_t]) -> [vector3_t]

public func acceleration_fn_for(
    config: simulation_config_t
) -> acceleration_fn_t {
    return { particles in compute_accelerations(particles: particles, config: config) }
}

public func step_euler(
    particles: inout [particle_t],
    timestep: Double,
    accelerations: [vector3_t]
) {
    for i in particles.indices {
        particles[i].velocity += accelerations[i] * timestep
        particles[i].position += particles[i].velocity * timestep
    }
}

public func step_velocity_verlet(
    particles: inout [particle_t],
    timestep: Double,
    accelerations: [vector3_t],
    acceleration_fn: acceleration_fn_t
) {
    for i in particles.indices {
        particles[i].position +=
            particles[i].velocity * timestep
            + accelerations[i] * (0.5 * timestep * timestep)
    }
    let fresh = acceleration_fn(particles)
    for i in particles.indices {
        particles[i].velocity += (accelerations[i] + fresh[i]) * (0.5 * timestep)
    }
}

public func step_runge_kutta4(
    particles: inout [particle_t],
    timestep: Double,
    acceleration_fn: acceleration_fn_t
) {
    let count = particles.count
    guard count > 0 else { return }
    let start_pos = particles.map { $0.position }
    let start_vel = particles.map { $0.velocity }

    func accelerations_at(_ positions: [vector3_t]) -> [vector3_t] {
        var probe = particles
        for i in probe.indices { probe[i].position = positions[i] }
        return acceleration_fn(probe)
    }

    let a1 = accelerations_at(start_pos)
    var pos2 = [vector3_t](repeating: vector3_t(), count: count)
    var vel2 = [vector3_t](repeating: vector3_t(), count: count)
    for i in 0..<count {
        pos2[i] =
            start_pos[i] + start_vel[i] * (timestep * 0.5)
            + a1[i] * (0.125 * timestep * timestep)
        vel2[i] = start_vel[i] + a1[i] * (timestep * 0.5)
    }
    let a2 = accelerations_at(pos2)
    var pos3 = [vector3_t](repeating: vector3_t(), count: count)
    var vel3 = [vector3_t](repeating: vector3_t(), count: count)
    for i in 0..<count {
        pos3[i] =
            start_pos[i] + vel2[i] * (timestep * 0.5)
            + a2[i] * (0.125 * timestep * timestep)
        vel3[i] = start_vel[i] + a2[i] * (timestep * 0.5)
    }
    let a3 = accelerations_at(pos3)
    var pos4 = [vector3_t](repeating: vector3_t(), count: count)
    var vel4 = [vector3_t](repeating: vector3_t(), count: count)
    for i in 0..<count {
        pos4[i] =
            start_pos[i] + vel3[i] * timestep
            + a3[i] * (0.5 * timestep * timestep)
        vel4[i] = start_vel[i] + a3[i] * timestep
    }
    let a4 = accelerations_at(pos4)
    for i in 0..<count {
        particles[i].position =
            start_pos[i]
            + (start_vel[i] + 2.0 * vel2[i] + 2.0 * vel3[i] + vel4[i]) * (timestep / 6.0)
        particles[i].velocity =
            start_vel[i]
            + (a1[i] + 2.0 * a2[i] + 2.0 * a3[i] + a4[i]) * (timestep / 6.0)
    }
}

public func integrate_step(
    particles: inout [particle_t],
    timestep: Double,
    config: simulation_config_t,
    acceleration_fn: acceleration_fn_t,
    cached_accelerations: [vector3_t]? = nil
) -> [vector3_t] {
    // stale cache from before particles were replaced must be ignored
    let cached_valid = cached_accelerations.flatMap {
        $0.count == particles.count ? $0 : nil
    }
    switch config.integrator {
    case .euler:
        let accels = cached_valid ?? acceleration_fn(particles)
        step_euler(particles: &particles, timestep: timestep, accelerations: accels)
        return acceleration_fn(particles)
    case .velocity_verlet:
        let accels = cached_valid ?? acceleration_fn(particles)
        step_velocity_verlet(
            particles: &particles, timestep: timestep,
            accelerations: accels, acceleration_fn: acceleration_fn)
        return acceleration_fn(particles)
    case .runge_kutta4:
        step_runge_kutta4(
            particles: &particles, timestep: timestep,
            acceleration_fn: acceleration_fn)
        return acceleration_fn(particles)
    }
}
