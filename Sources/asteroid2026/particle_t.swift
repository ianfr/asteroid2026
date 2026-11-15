public struct particle_t: Equatable, Sendable {
  public var id: Int
  public var asteroid_id: Int
  public var color: Int
  public var mass: Double
  public var radius: Double
  public var position: vector3_t
  public var velocity: vector3_t
  public var angular_velocity: vector3_t

  public init(
    id: Int = 0,
    asteroid_id: Int = 0,
    color: Int = 0,
    mass: Double = 1.0,
    radius: Double = 1.0,
    position: vector3_t = vector3_t(),
    velocity: vector3_t = vector3_t(),
    angular_velocity: vector3_t = vector3_t()
  ) {
    self.id = id
    self.asteroid_id = asteroid_id
    self.color = color
    self.mass = mass
    self.radius = radius
    self.position = position
    self.velocity = velocity
    self.angular_velocity = angular_velocity
  }
}
