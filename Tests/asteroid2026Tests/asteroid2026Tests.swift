import Foundation
import Testing

@testable import asteroid2026

@Test func main_clears_stale_output_and_accepts_missing_directory() throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("asteroid_output_\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let output = directory.appendingPathComponent("frames", isDirectory: true)
  try asteroid2026.clear_output_directory(output.path)
  let nested = output.appendingPathComponent("nested", isDirectory: true)
  try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
  try Data("stale".utf8).write(to: nested.appendingPathComponent("old.csv"))
  try Data("stale".utf8).write(to: output.appendingPathComponent("ast.csv.0000001000"))
  let sibling = directory.appendingPathComponent("keep.txt")
  try Data("keep".utf8).write(to: sibling)

  try asteroid2026.clear_output_directory(output.path)

  #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
  #expect(FileManager.default.fileExists(atPath: sibling.path))
  try asteroid2026.clear_output_directory(output.path)
}

@Test func vector_cross_is_right_handed_and_perpendicular() {
  let first = vector3_t(1, 2, 3)
  let second = vector3_t(4, -1, 2)
  let product = first.cross(second)
  #expect(product == vector3_t(7, 10, -9))
  #expect(product.dot(first) == 0)
  #expect(product.dot(second) == 0)
  #expect(vector3_t(0, 0, 1).cross(vector3_t(1, 0, 0)) == vector3_t(0, 1, 0))
}

@Test func builders_apply_rotation_about_requested_center() {
  let center = vector3_t(12, -8, 5)
  let translation = vector3_t(2, 3, -1)
  let spin = vector3_t(0.1, -0.2, 0.3)
  for packing in [packing_t.grid, .random_pack] {
    let simulation = simulation_t()
    simulation.add_spherical_asteroid(
      total_mass: 60, radius: 6, particle_radius: 1,
      center: center, velocity: translation, color: 0,
      packing: packing, seed: 42, angular_velocity: spin)
    simulation.add_ellipsoid_asteroid(
      total_mass: 60, semi_axes: vector3_t(6, 4, 5), particle_radius: 1,
      center: center, velocity: translation, color: 1,
      packing: packing, seed: 42, angular_velocity: spin)
    for asteroid_id in 0...1 {
      let particles = simulation.particles.filter { $0.asteroid_id == asteroid_id }
      #expect(!particles.isEmpty)
      for particle in particles {
        let offset = particle.position - center
        let rotational_velocity = particle.velocity - translation
        let expected = vector3_t(
          spin.y * offset.z - spin.z * offset.y,
          spin.z * offset.x - spin.x * offset.z,
          spin.x * offset.y - spin.y * offset.x)
        #expect((rotational_velocity - expected).norm() < 1e-12)
        #expect(abs(rotational_velocity.dot(offset)) < 1e-12)
        #expect(particle.angular_velocity == spin)
      }
    }
  }
}

@Test func bennu_collision_has_equal_bulk_densities_nearby_impactors_and_spin() {
  let simulation = asteroid2026.make_collision(first_seed: 1, second_seed: 2, third_seed: 3)
  #expect(simulation.config.cohesion.model == .spring)
  let radii = [245.0, 100.0, 75.0]
  let centers = [vector3_t(), vector3_t(365, 60, 0), vector3_t(-335, -50, 0)]
  let velocities = [vector3_t(), vector3_t(-0.12, 0, 0), vector3_t(0.10, 0, 0)]
  let expected_density = 7.329e10 / (4.0 / 3.0 * Double.pi * pow(radii[0], 3))
  let spin_rate = 2.0 * Double.pi / (4.296056 * 3600.0)
  #expect(Set(simulation.particles.map { $0.asteroid_id }) == Set([0, 1, 2]))
  for asteroid_id in 0...2 {
    let particles = simulation.particles.filter { $0.asteroid_id == asteroid_id }
    #expect(!particles.isEmpty)
    let mass = particles.reduce(0.0) { $0 + $1.mass }
    let density = mass / (4.0 / 3.0 * Double.pi * pow(radii[asteroid_id], 3))
    #expect(abs(density / expected_density - 1) < 1e-12)
    for particle in particles {
      let offset = particle.position - centers[asteroid_id]
      #expect(offset.norm() + particle.radius <= radii[asteroid_id] + 1e-9)
      if asteroid_id == 0 {
        let expected_velocity = vector3_t(-spin_rate * offset.y, spin_rate * offset.x, 0)
        #expect((particle.velocity - expected_velocity).norm() < 1e-12)
      } else {
        #expect(particle.velocity == velocities[asteroid_id])
      }
    }
    if asteroid_id > 0 {
      let surface_gap = centers[asteroid_id].norm() - radii[0] - radii[asteroid_id]
      #expect(surface_gap > 0 && surface_gap < 30)
      #expect(centers[asteroid_id].dot(velocities[asteroid_id]) < 0)
    }
  }
}

@Test func vector_add_and_norm() async throws {
  let a = vector3_t(1, 2, 3)
  let b = vector3_t(4, -1, 0)
  let sum = a + b
  #expect(sum == vector3_t(5, 1, 3))
  #expect(abs(a.norm() - 3.74165738677) < 1e-6)
  #expect(abs(a.dot(b) - 2.0) < 1e-9)
}

@Test func vector_normalized_zero_stays_zero() async throws {
  #expect(vector3_t().normalized() == vector3_t())
  let unit = vector3_t(2, 0, 0).normalized()
  #expect(abs(unit.x - 1.0) < 1e-12)
}

@Test func builder_sphere_contains_and_conserves_mass() async throws {
  let made = make_spherical_asteroid(
    total_mass: 100.0, radius: 10.0, particle_radius: 2.0,
    center: vector3_t(0, 0, 0), velocity: vector3_t(1, 0, 0),
    asteroid_id: 0, color: 3)
  #expect(!made.isEmpty)
  let total = made.reduce(0.0) { $0 + $1.mass }
  #expect(abs(total - 100.0) < 1e-6)
  for particle in made {
    #expect((particle.position - vector3_t(0, 0, 0)).norm() <= 10.0 + 1e-9)
    #expect(particle.velocity == vector3_t(1, 0, 0))
  }
  for (offset, particle) in made.enumerated() {
    #expect(particle.id == offset)
  }
}

@Test func builder_masses_split_evenly() async throws {
  let made = make_ellipsoid_asteroid(
    total_mass: 60.0, semi_axes: vector3_t(6, 4, 4), particle_radius: 1.0,
    center: vector3_t(5, 5, 5), velocity: vector3_t(),
    asteroid_id: 1, color: 0)
  #expect(!made.isEmpty)
  let first = made[0].mass
  for particle in made { #expect(abs(particle.mass - first) < 1e-12) }
}

@Test func gravity_single_particle_is_zero() async throws {
  let solo = [particle_t(position: vector3_t(0, 0, 0))]
  let accels = compute_accelerations_brute(
    particles: solo, gravitational_constant: 6.67430e-11, softening_length: 1e-3)
  #expect(accels.count == 1)
  #expect(accels[0].norm() == 0)
}

@Test func gravity_two_body_matches_newton() async throws {
  let big_g = 6.67430e-11
  let particles = [
    particle_t(mass: 1e10, radius: 1, position: vector3_t(0, 0, 0)),
    particle_t(mass: 2e10, radius: 1, position: vector3_t(10, 0, 0)),
  ]
  let accels = compute_accelerations_brute(
    particles: particles, gravitational_constant: big_g, softening_length: 0)
  #expect(accels[0].x > 0)
  #expect(accels[1].x < 0)
  let expect0 = big_g * 2e10 / 100.0
  #expect(abs(accels[0].x - expect0) / expect0 < 1e-9)
}

@Test func gravity_barnes_hut_matches_brute_for_two_bodies() async throws {
  var config = simulation_config_t()
  config.use_barnes_hut = true
  config.barnes_hut_threshold = 2
  config.barnes_hut_theta = 0.1
  let particles = [
    particle_t(mass: 1e10, radius: 1, position: vector3_t(0, 0, 0)),
    particle_t(mass: 2e10, radius: 1, position: vector3_t(10, 0, 0)),
    particle_t(mass: 1e10, radius: 1, position: vector3_t(0, 20, 0)),
  ]
  let fast = compute_accelerations(particles: particles, config: config)
  let slow = compute_accelerations_brute(
    particles: particles, gravitational_constant: config.gravitational_constant,
    softening_length: config.softening_length)
  #expect(fast.count == slow.count)
  for i in fast.indices {
    let diff = (fast[i] - slow[i]).norm()
    let scale = max(slow[i].norm(), 1e-12)
    #expect(diff / scale < 0.05)
  }
}

@Test func euler_moves_with_constant_acceleration() async throws {
  var particles = [particle_t(position: vector3_t(0, 0, 0), velocity: vector3_t(1, 0, 0))]
  step_euler(particles: &particles, timestep: 2.0, accelerations: [vector3_t(0, 1, 0)])
  #expect(particles[0].velocity == vector3_t(1, 2, 0))
  #expect(particles[0].position == vector3_t(2, 4, 0))
}

@Test func verlet_is_exact_for_constant_acceleration() async throws {
  var particles = [particle_t()]
  let accel_fn: acceleration_fn_t = { _ in [vector3_t(0, -2, 0)] }
  step_velocity_verlet(
    particles: &particles, timestep: 3.0,
    accelerations: [vector3_t(0, -2, 0)], acceleration_fn: accel_fn)
  #expect(abs(particles[0].position.y - (-9.0)) < 1e-9)
  #expect(abs(particles[0].velocity.y - (-6.0)) < 1e-9)
}

@Test func runge_kutta4_tracks_free_particle() async throws {
  var particles = [particle_t(velocity: vector3_t(3, 0, 0))]
  let accel_fn: acceleration_fn_t = { _ in [vector3_t()] }
  step_runge_kutta4(particles: &particles, timestep: 2.0, acceleration_fn: accel_fn)
  #expect(abs(particles[0].position.x - 6.0) < 1e-9)
  #expect(abs(particles[0].velocity.x - 3.0) < 1e-12)
}

@Test func collision_head_on_applies_restitution() async throws {
  var particles = [
    particle_t(mass: 1, radius: 1, position: vector3_t(-0.5, 0, 0), velocity: vector3_t(2, 0, 0)),
    particle_t(mass: 1, radius: 1, position: vector3_t(0.5, 0, 0), velocity: vector3_t(-2, 0, 0)),
  ]
  particles[0].id = 0
  particles[1].id = 1
  let events = [collision_event_t(index_a: 0, index_b: 1, penetration: 1.0, distance: 1.0)]
  resolve_collision_events(
    particles: &particles, events: events,
    restitution: 1.0, positional_correction: 0.0)
  #expect(abs(particles[0].velocity.x - (-2.0)) < 1e-9)
  #expect(abs(particles[1].velocity.x - 2.0) < 1e-9)
}

@Test func collision_separating_pair_is_untouched() async throws {
  var particles = [
    particle_t(mass: 1, radius: 1, position: vector3_t(-0.5, 0, 0), velocity: vector3_t(-2, 0, 0)),
    particle_t(mass: 1, radius: 1, position: vector3_t(0.5, 0, 0), velocity: vector3_t(2, 0, 0)),
  ]
  let before = particles
  let events = [collision_event_t(index_a: 0, index_b: 1, penetration: 1.0, distance: 1.0)]
  resolve_collision_events(
    particles: &particles, events: events,
    restitution: 0.86, positional_correction: 0.0)
  #expect(particles == before)
}

@Test func detector_finds_overlap_and_sorts_by_penetration() async throws {
  let particles = [
    particle_t(radius: 1, position: vector3_t(0, 0, 0)),
    particle_t(radius: 1, position: vector3_t(1.0, 0, 0)),
    particle_t(radius: 1, position: vector3_t(50, 0, 0)),
  ]
  let events = detect_collision_events(particles: particles, separation_buffer: 0.05)
  #expect(events.count == 1)
  #expect(events[0].index_a == 0 && events[0].index_b == 1)
  #expect(events[0].penetration > 0)
}

@Test func detector_misses_nothing_in_dense_clump() async throws {
  var particles = [particle_t]()
  for x in 0..<3 {
    for y in 0..<3 {
      particles.append(
        particle_t(
          radius: 1.0, position: vector3_t(Double(x) * 1.5, Double(y) * 1.5, 0)))
    }
  }
  let events = detect_collision_events(particles: particles, separation_buffer: 0.0)
  #expect(!events.isEmpty)
  var touched = Set<Int>()
  for event in events {
    touched.insert(event.index_a)
    touched.insert(event.index_b)
  }
  #expect(touched.count == particles.count)
}

@Test func batching_never_shares_a_particle_within_one_batch() async throws {
  let events = [
    collision_event_t(index_a: 0, index_b: 1, penetration: 3, distance: 1),
    collision_event_t(index_a: 1, index_b: 2, penetration: 2, distance: 1),
    collision_event_t(index_a: 2, index_b: 3, penetration: 1, distance: 1),
  ]
  let batches = group_independent_batches(events: events)
  #expect(batches.count == 2)
  for batch in batches {
    var seen = Set<Int>()
    for event in batch {
      #expect(!seen.contains(event.index_a))
      #expect(!seen.contains(event.index_b))
      seen.insert(event.index_a)
      seen.insert(event.index_b)
    }
  }
}

@Test func adaptive_steps_stay_within_bounds() async throws {
  let particles = [
    particle_t(radius: 5, velocity: vector3_t(10, 0, 0)),
    particle_t(radius: 5, velocity: vector3_t(-4, 0, 0)),
  ]
  let by_max = next_timestep_max(particles: particles, upper_bound: 0.15, lower_bound: 1e-5)
  let by_mean = next_timestep_mean(particles: particles, upper_bound: 0.15, lower_bound: 1e-5)
  #expect(by_max >= 1e-5 && by_max <= 0.15)
  #expect(by_mean >= 1e-5 && by_mean <= 0.15)
}

@Test func csv_round_trip_preserves_state() async throws {
  let particles = [
    particle_t(
      id: 7, asteroid_id: 2, color: 5, mass: 3.25, radius: 1.5,
      position: vector3_t(1, 2, 3), velocity: vector3_t(4, 5, 6))
  ]
  let path = FileManager.default.temporaryDirectory
    .appendingPathComponent("asteroid_csv_test.\(Int.random(in: 0..<1_000_000)).csv").path
  try write_particles_csv(particles: particles, path: path)
  let back = try read_particles_csv(path: path)
  try? FileManager.default.removeItem(atPath: path)
  #expect(back.count == 1)
  #expect(back[0].id == 7)
  #expect(abs(back[0].position.x - 1.0) < 1e-9)
  #expect(abs(back[0].velocity.z - 6.0) < 1e-9)
  #expect(abs(back[0].mass - 3.25) < 1e-9)
}

@Test func simulation_brings_two_bodies_together() async throws {
  var config = simulation_config_t()
  config.use_barnes_hut = false
  config.gravitational_constant = 10.0
  config.integrator = .velocity_verlet
  config.adaptive_mode = .fixed
  config.max_timestep = 0.01
  config.collision_iterations = 1
  config.separation_buffer = 0.0
  let simulation = simulation_t(config: config)
  simulation.add_asteroid([
    particle_t(id: 0, mass: 100, radius: 0.5, position: vector3_t(-5, 0, 0)),
    particle_t(id: 1, mass: 100, radius: 0.5, position: vector3_t(5, 0, 0)),
  ])
  let start_gap = (simulation.particles[0].position - simulation.particles[1].position).norm()
  for _ in 0..<20 { simulation.advance(timestep: simulation.current_timestep()) }
  let end_gap = (simulation.particles[0].position - simulation.particles[1].position).norm()
  #expect(end_gap < start_gap)
}

@Test func simulation_collision_removes_deep_overlap() async throws {
  var config = simulation_config_t()
  config.use_barnes_hut = false
  config.gravitational_constant = 0
  config.integrator = .euler
  config.adaptive_mode = .fixed
  config.max_timestep = 0.001
  var particles = [
    particle_t(
      id: 0, mass: 1, radius: 1, position: vector3_t(-0.9, 0, 0), velocity: vector3_t(1, 0, 0)),
    particle_t(
      id: 1, mass: 1, radius: 1, position: vector3_t(0.9, 0, 0), velocity: vector3_t(-1, 0, 0)),
  ]
  handle_collisions(particles: &particles, config: config)
  let gap = (particles[0].position - particles[1].position).norm()
  #expect(gap >= 1.8)
}

@Test func random_pack_stays_inside_and_conserves_mass() async throws {
  let made = make_spherical_asteroid(
    total_mass: 100.0, radius: 10.0, particle_radius: 1.0,
    center: vector3_t(5, 0, 0), velocity: vector3_t(),
    asteroid_id: 2, color: 1, packing: .random_pack, seed: 42)
  #expect(!made.isEmpty)
  let total = made.reduce(0.0) { $0 + $1.mass }
  #expect(abs(total - 100.0) < 1e-6)
  for (offset, particle) in made.enumerated() {
    #expect(particle.id == offset)
    let dist = (particle.position - vector3_t(5, 0, 0)).norm()
    #expect(dist + particle.radius <= 10.0 + 1e-9)
  }
  for i in 0..<made.count {
    for j in (i + 1)..<made.count {
      let gap = (made[i].position - made[j].position).norm()
      #expect(gap >= made[i].radius + made[j].radius - 1e-9)
    }
  }
}

@Test func random_pack_is_deterministic_for_same_seed() async throws {
  let first = make_spherical_asteroid(
    total_mass: 50.0, radius: 8.0, particle_radius: 1.0,
    center: vector3_t(), velocity: vector3_t(),
    asteroid_id: 0, color: 0, packing: .random_pack, seed: 7)
  let second = make_spherical_asteroid(
    total_mass: 50.0, radius: 8.0, particle_radius: 1.0,
    center: vector3_t(), velocity: vector3_t(),
    asteroid_id: 0, color: 0, packing: .random_pack, seed: 7)
  #expect(first == second)
}

@Test func normal_radii_follow_uniform_density() async throws {
  let made = make_spherical_asteroid(
    total_mass: 90.0, radius: 12.0, particle_radius: 1.0,
    center: vector3_t(), velocity: vector3_t(),
    asteroid_id: 0, color: 0, radius_spread: 0.2, seed: 11)
  #expect(!made.isEmpty)
  let total = made.reduce(0.0) { $0 + $1.mass }
  #expect(abs(total - 90.0) < 1e-6)
  let density = made[0].mass / (made[0].radius * made[0].radius * made[0].radius)
  for particle in made {
    #expect(particle.radius > 0)
    let other = particle.mass / (particle.radius * particle.radius * particle.radius)
    #expect(abs(other - density) / density < 1e-9)
  }
  let mean_radius = made.reduce(0.0) { $0 + $1.radius } / Double(made.count)
  #expect(abs(mean_radius - 1.0) < 0.15)
}

@Test func normal_radii_vary_between_particles() async throws {
  let made = make_spherical_asteroid(
    total_mass: 90.0, radius: 12.0, particle_radius: 1.0,
    center: vector3_t(), velocity: vector3_t(),
    asteroid_id: 0, color: 0, radius_spread: 0.3, seed: 13)
  let radii = Set(made.map { $0.radius })
  #expect(radii.count > 1)
}

@Test func simulation_add_matches_main_wiring() async throws {
  let simulation = simulation_t()
  simulation.add_spherical_asteroid(
    total_mass: 60.0, radius: 9.0, particle_radius: 1.0,
    center: vector3_t(), velocity: vector3_t(), color: 0,
    packing: .random_pack, radius_spread: 0.2, seed: 101)
  #expect(!simulation.particles.isEmpty)
  let total = simulation.particles.reduce(0.0) { $0 + $1.mass }
  #expect(abs(total - 60.0) < 1e-6)
  let radii = Set(simulation.particles.map { $0.radius })
  #expect(radii.count > 1)
  for (offset, particle) in simulation.particles.enumerated() {
    #expect(particle.id == offset)
    let dist = particle.position.norm()
    #expect(dist + particle.radius <= 9.0 + 1e-9)
  }
}

@Test func cohesion_none_forms_no_bonds() async throws {
  var config = cohesion_config_t()
  config.model = .none
  var state = cohesion_state_t()
  let pair = [
    particle_t(id: 0, mass: 1, radius: 1, position: vector3_t()),
    particle_t(id: 1, mass: 1, radius: 1, position: vector3_t(1, 0, 0)),
  ]
  update_cohesion_bonds(particles: pair, state: &state, config: config)
  #expect(state.bonds.isEmpty)
  #expect(
    cohesion_accelerations(particles: pair, bonds: state.bonds, config: config)
      == [vector3_t(), vector3_t()])
}

@Test func cohesion_spring_bonds_slow_neighbors() async throws {
  var config = cohesion_config_t()
  config.model = .spring
  var state = cohesion_state_t()
  let pair = [
    particle_t(id: 0, mass: 1, radius: 1, position: vector3_t()),
    particle_t(
      id: 1, mass: 1, radius: 1, position: vector3_t(2, 0, 0),
      velocity: vector3_t(0.1, 0, 0)),
  ]
  update_cohesion_bonds(particles: pair, state: &state, config: config)
  #expect(state.bonds.count == 1)
  let pull = cohesion_accelerations(particles: pair, bonds: state.bonds, config: config)
  #expect(pull[0].x > 0)
  #expect(pull[1].x < 0)
  #expect(abs(pull[0].x + pull[1].x) < 1e-9)
}

@Test func cohesion_spring_ignores_fast_pairs() async throws {
  var config = cohesion_config_t()
  config.model = .spring
  var state = cohesion_state_t()
  let pair = [
    particle_t(id: 0, mass: 1e7, radius: 10, position: vector3_t()),
    particle_t(
      id: 1, mass: 1e7, radius: 10, position: vector3_t(15, 0, 0),
      velocity: vector3_t(100, 0, 0)),
  ]
  update_cohesion_bonds(particles: pair, state: &state, config: config)
  #expect(state.bonds.isEmpty)
}

@Test func cohesion_spring_breaks_past_threshold() async throws {
  var config = cohesion_config_t()
  config.model = .spring
  var state = cohesion_state_t()
  let resting = [
    particle_t(id: 0, mass: 1, radius: 1, position: vector3_t()),
    particle_t(id: 1, mass: 1, radius: 1, position: vector3_t(2, 0, 0)),
  ]
  update_cohesion_bonds(particles: resting, state: &state, config: config)
  #expect(state.bonds.count == 1)
  let kicked = [
    particle_t(id: 0, mass: 1, radius: 1, position: vector3_t()),
    particle_t(
      id: 1, mass: 1, radius: 1, position: vector3_t(2, 0, 0),
      velocity: vector3_t(1e8, 0, 0)),
  ]
  update_cohesion_bonds(particles: kicked, state: &state, config: config)
  #expect(state.bonds.isEmpty)
}

@Test func cohesion_break_clamps_to_connect() async throws {
  var config = cohesion_config_t()
  config.model = .spring
  config.connect_momentum = 10.0
  config.break_momentum = 1.0
  var state = cohesion_state_t()
  let pair = [
    particle_t(id: 0, mass: 1, radius: 1, position: vector3_t()),
    particle_t(
      id: 1, mass: 1, radius: 1, position: vector3_t(2, 0, 0),
      velocity: vector3_t(6, 0, 0)),
  ]
  update_cohesion_bonds(particles: pair, state: &state, config: config)
  #expect(state.bonds.count == 1)
}

@Test func simulation_spring_cohesion_bonds_touching_pair() async throws {
  var config = simulation_config_t()
  config.use_barnes_hut = false
  config.gravitational_constant = 0
  config.integrator = .euler
  config.adaptive_mode = .fixed
  config.max_timestep = 0.001
  config.collision_iterations = 0
  config.cohesion.model = .spring
  config.cohesion.connect_momentum = 1e9
  let simulation = simulation_t(config: config)
  simulation.add_asteroid([
    particle_t(id: 0, mass: 1, radius: 1, position: vector3_t(-1.1, 0, 0)),
    particle_t(id: 1, mass: 1, radius: 1, position: vector3_t(1.1, 0, 0)),
  ])
  simulation.advance(timestep: simulation.current_timestep())
  #expect(simulation.cohesion_bond_count == 1)
  #expect(simulation.particles[0].velocity.x > 0)
  #expect(simulation.particles[1].velocity.x < 0)
}

@Test func simulation_gravity_only_stays_bond_free() async throws {
  var config = simulation_config_t()
  config.use_barnes_hut = false
  config.gravitational_constant = 0
  config.integrator = .runge_kutta4
  config.adaptive_mode = .fixed
  config.max_timestep = 0.001
  config.collision_iterations = 0
  let simulation = simulation_t(config: config)
  simulation.add_asteroid([
    particle_t(id: 0, mass: 1, radius: 1, position: vector3_t(-1, 0, 0)),
    particle_t(id: 1, mass: 1, radius: 1, position: vector3_t(1, 0, 0)),
  ])
  simulation.advance(timestep: simulation.current_timestep())
  #expect(simulation.cohesion_bond_count == 0)
  #expect(simulation.particles[0].velocity == vector3_t())
  #expect(simulation.particles[1].velocity == vector3_t())
}
