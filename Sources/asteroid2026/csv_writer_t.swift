import Foundation

public let csv_header_t = "rx,ry,rz,vx,vy,vz,mass,radius,id,ast_id,col_ast"

public func csv_line_for(_ particle: particle_t) -> String {
  return "\(particle.position.x),\(particle.position.y),\(particle.position.z),"
    + "\(particle.velocity.x),\(particle.velocity.y),\(particle.velocity.z),"
    + "\(particle.mass),\(particle.radius),"
    + "\(particle.id),\(particle.asteroid_id),\(particle.color)"
}

public func write_particles_csv(particles: [particle_t], path: String) throws {
  var lines = [csv_header_t]
  lines.reserveCapacity(particles.count + 1)
  for particle in particles { lines.append(csv_line_for(particle)) }
  try lines.joined(separator: "\n").appending("\n").write(
    toFile: path, atomically: true, encoding: .utf8)
}

public func read_particles_csv(path: String) throws -> [particle_t] {
  let text = try String(contentsOfFile: path, encoding: .utf8)
  var rows = text.components(separatedBy: .newlines)
  rows = rows.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
  guard !rows.isEmpty else { return [] }
  let start = rows[0].hasPrefix("rx") ? 1 : 0
  var out = [particle_t]()
  for line in rows[start...] {
    let fields = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard fields.count >= 11 else { continue }
    guard let rx = Double(fields[0]), let ry = Double(fields[1]),
      let rz = Double(fields[2]), let vx = Double(fields[3]),
      let vy = Double(fields[4]), let vz = Double(fields[5]),
      let mass = Double(fields[6]), let radius = Double(fields[7]),
      let id = Int(fields[8]), let ast = Int(fields[9]),
      let color = Int(fields[10])
    else { continue }
    out.append(
      particle_t(
        id: id, asteroid_id: ast, color: color, mass: mass, radius: radius,
        position: vector3_t(rx, ry, rz), velocity: vector3_t(vx, vy, vz)))
  }
  return out
}

public func paraview_frame_path(directory: String, frame: Int) -> String {
  return directory + "/ast.csv." + String(format: "%010d", frame)
}
