import Foundation

public enum packing_t: Sendable {
  case grid
  case random_pack
}

public struct seeded_rng_t: RandomNumberGenerator, Sendable {
  public var state: UInt64

  public init(seed: UInt64) {
    self.state = seed == 0 ? 0x9e37_79b9_7f4a_7c15 : seed
  }

  public mutating func next() -> UInt64 {
    state &+= 0x9e37_79b9_7f4a_7c15
    var mixed = state
    mixed = (mixed ^ (mixed >> 30)) &* 0xbf58_476d_1ce4_e5b9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94d0_49bb_1331_11eb
    return mixed ^ (mixed >> 31)
  }
}

public func sample_normal(
  mean: Double, standard_deviation: Double, rng: inout seeded_rng_t
) -> Double {
  var first = 0.0
  while first <= 0 {
    first = Double.random(in: 0..<1, using: &rng)
  }
  let second = Double.random(in: 0..<1, using: &rng)
  let radius = (-2.0 * log(first)).squareRoot()
  return mean + standard_deviation * radius * cos(2.0 * Double.pi * second)
}

public func sample_radius(
  mean_radius: Double, radius_spread: Double, rng: inout seeded_rng_t
) -> Double {
  if radius_spread <= 0 {
    return mean_radius
  }
  for _ in 0..<100 {
    let drawn = sample_normal(
      mean: mean_radius, standard_deviation: radius_spread, rng: &rng)
    if drawn > 0 {
      return drawn
    }
  }
  return max(mean_radius * 0.05, 1e-9)
}

public func point_in_ellipsoid(
  semi_axes: vector3_t, center: vector3_t, rng: inout seeded_rng_t
) -> vector3_t {
  var direction = vector3_t()
  var length_squared = 0.0
  while length_squared <= 1e-12 || length_squared > 1 {
    direction = vector3_t(
      sample_normal(mean: 0, standard_deviation: 1, rng: &rng),
      sample_normal(mean: 0, standard_deviation: 1, rng: &rng),
      sample_normal(mean: 0, standard_deviation: 1, rng: &rng))
    length_squared = direction.norm_squared()
  }
  let scale =
    pow(Double.random(in: 0..<1, using: &rng), 1.0 / 3.0)
    / length_squared.squareRoot()
  return vector3_t(
    center.x + direction.x * scale * semi_axes.x,
    center.y + direction.y * scale * semi_axes.y,
    center.z + direction.z * scale * semi_axes.z)
}

public func reassign_ids(particles: inout [particle_t], start_id: Int = 0) {
  for i in particles.indices {
    particles[i].id = start_id + i
  }
}

private func assign_uniform_density_masses(
  particles: inout [particle_t], total_mass: Double
) {
  var weight_sum = 0.0
  for particle in particles {
    weight_sum += particle.radius * particle.radius * particle.radius
  }
  guard weight_sum > 0 else { return }
  for i in particles.indices {
    let weight = particles[i].radius * particles[i].radius * particles[i].radius
    particles[i].mass = total_mass * weight / weight_sum
  }
}

public func make_ellipsoid_asteroid(
  total_mass: Double,
  semi_axes: vector3_t,
  particle_radius: Double,
  center: vector3_t,
  velocity: vector3_t,
  asteroid_id: Int,
  color: Int,
  start_id: Int = 0,
  spacing_buffer: Double = 0.001,
  packing: packing_t = .grid,
  radius_spread: Double = 0,
  volume_fraction: Double = 0.55,
  seed: UInt64 = 0,
  angular_velocity: vector3_t = vector3_t()
) -> [particle_t] {
  guard semi_axes.x > 0, semi_axes.y > 0, semi_axes.z > 0,
    particle_radius > 0
  else { return [] }
  var rng = seeded_rng_t(seed: seed)
  var particles = [particle_t]()
  switch packing {
  case .grid:
    // wide spacing when radii vary so large samples do not overlap
    let footprint = particle_radius + 2.0 * radius_spread
    let step = 2.0 * footprint + spacing_buffer
    var x = center.x - semi_axes.x
    while x <= center.x + semi_axes.x {
      var y = center.y - semi_axes.y
      while y <= center.y + semi_axes.y {
        var z = center.z - semi_axes.z
        while z <= center.z + semi_axes.z {
          let dx = (x - center.x) / semi_axes.x
          let dy = (y - center.y) / semi_axes.y
          let dz = (z - center.z) / semi_axes.z
          if dx * dx + dy * dy + dz * dz <= 1.0 {
            particles.append(
              particle_t(
                id: start_id + particles.count,
                asteroid_id: asteroid_id,
                color: color,
                mass: 1.0,
                radius: sample_radius(
                  mean_radius: particle_radius,
                  radius_spread: radius_spread, rng: &rng),
                position: vector3_t(x, y, z),
                velocity: velocity))
          }
          z += step
        }
        y += step
      }
      x += step
    }
  case .random_pack:
    let body_volume =
      4.0 / 3.0 * Double.pi
      * semi_axes.x * semi_axes.y * semi_axes.z
    let mean_volume =
      4.0 / 3.0 * Double.pi
      * particle_radius * particle_radius * particle_radius
    let target = Int((volume_fraction * body_volume / mean_volume).rounded(.down))
    var placed = [particle_t]()
    for _ in 0..<max(target, 0) {
      let radius = sample_radius(
        mean_radius: particle_radius,
        radius_spread: radius_spread, rng: &rng)
      for _ in 0..<200 {
        // shrink the sampling region so surfaces stay inside the body
        let inner = vector3_t(
          max(semi_axes.x - radius, 1e-9),
          max(semi_axes.y - radius, 1e-9),
          max(semi_axes.z - radius, 1e-9))
        let spot = point_in_ellipsoid(
          semi_axes: inner, center: center, rng: &rng)
        var overlaps = false
        for other in placed {
          let gap = (spot - other.position).norm()
          if gap < radius + other.radius + spacing_buffer {
            overlaps = true
            break
          }
        }
        if !overlaps {
          placed.append(
            particle_t(
              id: 0, asteroid_id: asteroid_id, color: color,
              mass: 1.0, radius: radius,
              position: spot, velocity: velocity))
          break
        }
      }
    }
    particles = placed
  }
  guard !particles.isEmpty else { return [] }
  if radius_spread <= 0 {
    let per_particle = total_mass / Double(particles.count)
    for i in particles.indices { particles[i].mass = per_particle }
  } else {
    assign_uniform_density_masses(particles: &particles, total_mass: total_mass)
  }
  reassign_ids(particles: &particles, start_id: start_id)
  // Bulk rotation needs orbital velocities as well as each sphere's own spin.
  for i in particles.indices {
    particles[i].velocity += angular_velocity.cross(particles[i].position - center)
    particles[i].angular_velocity = angular_velocity
  }
  return particles
}

public func make_spherical_asteroid(
  total_mass: Double,
  radius: Double,
  particle_radius: Double,
  center: vector3_t,
  velocity: vector3_t,
  asteroid_id: Int,
  color: Int,
  start_id: Int = 0,
  spacing_buffer: Double = 0.001,
  packing: packing_t = .grid,
  radius_spread: Double = 0,
  volume_fraction: Double = 0.55,
  seed: UInt64 = 0,
  angular_velocity: vector3_t = vector3_t()
) -> [particle_t] {
  return make_ellipsoid_asteroid(
    total_mass: total_mass,
    semi_axes: vector3_t(radius, radius, radius),
    particle_radius: particle_radius,
    center: center, velocity: velocity,
    asteroid_id: asteroid_id, color: color,
    start_id: start_id, spacing_buffer: spacing_buffer,
    packing: packing, radius_spread: radius_spread,
    volume_fraction: volume_fraction, seed: seed, angular_velocity: angular_velocity)
}
