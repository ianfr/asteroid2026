import Testing

@testable import asteroid2026

// Run with `swift test --sanitize=thread --filter cohesion_parallel` to detect races.
@Test func cohesion_parallel_preserves_every_independent_bond_force() {
    var config = cohesion_config_t()
    config.model = .spring
    config.spring_stiffness = 8
    config.spring_damping = 4
    var particles = [particle_t]()
    var bonds = Set<bond_t>()
    var expected = [vector3_t]()
    for pair_index in 0..<1024 {
        let first_index = particles.count
        let separation = Double(3 + pair_index % 5)
        let speed = Double(pair_index % 7 - 3) / 4
        let first_mass = Double(1 + pair_index % 3)
        let second_mass = Double(2 + pair_index % 5)
        particles.append(particle_t(id: first_index, mass: first_mass))
        particles.append(
            particle_t(
                id: first_index + 1, mass: second_mass,
                position: vector3_t(separation, 0, 0), velocity: vector3_t(speed, 0, 0)))
        bonds.insert(bond_t(index_a: first_index, index_b: first_index + 1, rest_length: 2))
        let force = 8 * (separation - 2) + 4 * speed
        expected.append(vector3_t(force / first_mass, 0, 0))
        expected.append(vector3_t(-force / second_mass, 0, 0))
    }

    for _ in 0..<16 {
        let actual = cohesion_accelerations(particles: particles, bonds: bonds, config: config)
        #expect(actual == expected)
    }
}

private func make_parallel_cohesion_fixture() -> (
    particles: [particle_t], bonds: Set<bond_t>, config: cohesion_config_t
) {
    var config = cohesion_config_t()
    config.model = .spring
    config.spring_stiffness = 13
    config.spring_damping = 3
    var particles = [particle_t]()
    for index in 0..<96 {
        let position = vector3_t(
            Double(index % 8), Double(index / 8), Double(index % 3) / 2)
        let velocity = vector3_t(
            Double(index % 5) / 4, -Double(index % 7) / 8, Double(index % 11) / 16)
        particles.append(
            particle_t(
                id: index, mass: Double(1 + index % 7), position: position, velocity: velocity))
    }
    var bonds = Set<bond_t>()
    for first_index in particles.indices {
        for second_index in (first_index + 1)..<particles.count {
            bonds.insert(
                bond_t(
                    index_a: first_index, index_b: second_index,
                    rest_length: Double(1 + (first_index + second_index) % 5)))
        }
        // Skipped iterations must leave their preallocated force slots at zero.
        bonds.insert(bond_t(index_a: first_index, index_b: first_index, rest_length: 1))
        bonds.insert(bond_t(index_a: first_index, index_b: particles.count, rest_length: 1))
    }
    return (particles, bonds, config)
}

private func serial_cohesion_accelerations(
    particles: [particle_t], bonds: Set<bond_t>, config: cohesion_config_t
) -> [vector3_t] {
    var result = [vector3_t](repeating: vector3_t(), count: particles.count)
    for bond in bonds {
        guard bond.index_a < particles.count, bond.index_b < particles.count else { continue }
        let first = particles[bond.index_a]
        let second = particles[bond.index_b]
        let offset = second.position - first.position
        let distance = offset.norm()
        guard distance > 1e-12 else { continue }
        let direction = offset / distance
        let spring_force = config.spring_stiffness * (distance - bond.rest_length)
        let damping_force =
            config.spring_damping * (second.velocity - first.velocity).dot(direction)
        let force = direction * (spring_force + damping_force)
        result[bond.index_a] += force / first.mass
        result[bond.index_b] -= force / second.mass
    }
    return result
}

@Test func cohesion_parallel_shared_particles_match_serial_accumulation() {
    let fixture = make_parallel_cohesion_fixture()
    let expected = serial_cohesion_accelerations(
        particles: fixture.particles, bonds: fixture.bonds, config: fixture.config)

    for _ in 0..<24 {
        let actual = cohesion_accelerations(
            particles: fixture.particles, bonds: fixture.bonds, config: fixture.config)
        #expect(actual == expected)
        let total_force = zip(fixture.particles, actual).reduce(vector3_t()) {
            $0 + $1.1 * $1.0.mass
        }
        #expect(total_force.norm() < 1e-8)
    }
}

@Test func cohesion_parallel_simultaneous_calls_match_serial_results() async {
    let fixture = make_parallel_cohesion_fixture()
    let expected = serial_cohesion_accelerations(
        particles: fixture.particles, bonds: fixture.bonds, config: fixture.config)

    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<8 {
            group.addTask {
                for _ in 0..<8 {
                    let actual = cohesion_accelerations(
                        particles: fixture.particles, bonds: fixture.bonds, config: fixture.config)
                    #expect(actual == expected)
                }
            }
        }
    }
}
