import Foundation

public struct vector3_t: Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var z: Double

  public init(_ x: Double = 0, _ y: Double = 0, _ z: Double = 0) {
    self.x = x
    self.y = y
    self.z = z
  }

  public func dot(_ other: vector3_t) -> Double {
    return x * other.x + y * other.y + z * other.z
  }

  public func cross(_ other: vector3_t) -> vector3_t {
    return vector3_t(
      y * other.z - z * other.y,
      z * other.x - x * other.z,
      x * other.y - y * other.x)
  }

  public func norm_squared() -> Double {
    return dot(self)
  }

  public func norm() -> Double {
    return norm_squared().squareRoot()
  }

  public func normalized() -> vector3_t {
    let n = norm()
    guard n > 0 else { return vector3_t() }
    return self / n
  }
}

public func + (_ a: vector3_t, _ b: vector3_t) -> vector3_t {
  return vector3_t(a.x + b.x, a.y + b.y, a.z + b.z)
}

public func - (_ a: vector3_t, _ b: vector3_t) -> vector3_t {
  return vector3_t(a.x - b.x, a.y - b.y, a.z - b.z)
}

public func * (_ a: vector3_t, _ s: Double) -> vector3_t {
  return vector3_t(a.x * s, a.y * s, a.z * s)
}

public func * (_ s: Double, _ a: vector3_t) -> vector3_t {
  return a * s
}

public func / (_ a: vector3_t, _ s: Double) -> vector3_t {
  return vector3_t(a.x / s, a.y / s, a.z / s)
}

public func += (_ a: inout vector3_t, _ b: vector3_t) {
  a = a + b
}

public func -= (_ a: inout vector3_t, _ b: vector3_t) {
  a = a - b
}
