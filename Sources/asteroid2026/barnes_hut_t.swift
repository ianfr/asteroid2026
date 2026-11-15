public final class octree_node_t: @unchecked Sendable {
    public var center: vector3_t
    public var half_extent: Double
    public var total_mass: Double = 0
    public var center_of_mass: vector3_t = vector3_t()
    public var particle_index: Int? = nil
    public var children: [octree_node_t?] = [nil, nil, nil, nil, nil, nil, nil, nil]

    public init(center: vector3_t, half_extent: Double) {
        self.center = center
        self.half_extent = half_extent
    }

    public var is_leaf: Bool {
        return children.allSatisfy { $0 == nil }
    }

    private func child_index(for position: vector3_t) -> Int {
        var index = 0
        if position.x >= center.x { index |= 1 }
        if position.y >= center.y { index |= 2 }
        if position.z >= center.z { index |= 4 }
        return index
    }

    private func make_child(at index: Int) -> octree_node_t {
        let quarter = half_extent / 2.0
        let ox = (index & 1) == 0 ? -quarter : quarter
        let oy = (index & 2) == 0 ? -quarter : quarter
        let oz = (index & 4) == 0 ? -quarter : quarter
        return octree_node_t(
            center: vector3_t(center.x + ox, center.y + oy, center.z + oz),
            half_extent: quarter
        )
    }

    public func insert(
        particle_index new_index: Int,
        particles: [particle_t],
        masses: [Double],
        positions: [vector3_t]
    ) {
        if is_leaf && particle_index == nil {
            particle_index = new_index
            return
        }
        if is_leaf {
            let existing = particle_index!
            particle_index = nil
            let first = children[child_index(for: positions[existing])] != nil
            _ = first
            var child = children[child_index(for: positions[existing])]
            if child == nil {
                child = make_child(at: child_index(for: positions[existing]))
                children[child_index(for: positions[existing])] = child
            }
            child!.insert(
                particle_index: existing, particles: particles,
                masses: masses, positions: positions)
            var second = children[child_index(for: positions[new_index])]
            if second == nil {
                second = make_child(at: child_index(for: positions[new_index]))
                children[child_index(for: positions[new_index])] = second
            }
            second!.insert(
                particle_index: new_index, particles: particles,
                masses: masses, positions: positions)
            return
        }
        let index = child_index(for: positions[new_index])
        if children[index] == nil {
            children[index] = make_child(at: index)
        }
        children[index]!.insert(
            particle_index: new_index, particles: particles,
            masses: masses, positions: positions)
    }

    public func summarize(masses: [Double], positions: [vector3_t]) {
        if is_leaf {
            if let single = particle_index {
                total_mass = masses[single]
                center_of_mass = positions[single]
            }
            else {
                total_mass = 0
                center_of_mass = center
            }
            return
        }
        total_mass = 0
        var weighted = vector3_t()
        for child in children {
            guard let child else { continue }
            child.summarize(masses: masses, positions: positions)
            total_mass += child.total_mass
            weighted += child.center_of_mass * child.total_mass
        }
        center_of_mass = total_mass > 0 ? weighted / total_mass : center
    }

    public func acceleration_on(
        target_index: Int,
        target_position: vector3_t,
        theta: Double,
        softening_squared: Double,
        gravitational_constant: Double
    ) -> vector3_t {
        if total_mass == 0 { return vector3_t() }
        if is_leaf {
            if particle_index == target_index { return vector3_t() }
            return point_acceleration(
                from: center_of_mass, mass: total_mass,
                to: target_position, softening_squared: softening_squared,
                gravitational_constant: gravitational_constant)
        }
        let offset = center_of_mass - target_position
        let distance = offset.norm()
        let size = half_extent * 2.0
        if size / max(distance, 1e-12) < theta {
            if distance * distance < softening_squared, total_mass_is_single_target(target_index) {
                return vector3_t()
            }
            return point_acceleration(
                from: center_of_mass, mass: total_mass,
                to: target_position, softening_squared: softening_squared,
                gravitational_constant: gravitational_constant)
        }
        var total = vector3_t()
        for child in children {
            guard let child else { continue }
            total += child.acceleration_on(
                target_index: target_index, target_position: target_position,
                theta: theta, softening_squared: softening_squared,
                gravitational_constant: gravitational_constant)
        }
        return total
    }

    private func total_mass_is_single_target(_ target: Int) -> Bool {
        if is_leaf { return particle_index == target }
        return false
    }

    private func point_acceleration(
        from source: vector3_t, mass: Double, to target: vector3_t,
        softening_squared: Double, gravitational_constant: Double
    ) -> vector3_t {
        let offset = source - target
        let dist_squared = offset.norm_squared() + softening_squared
        guard dist_squared > 0 else { return vector3_t() }
        let dist = dist_squared.squareRoot()
        return offset * (gravitational_constant * mass / (dist_squared * dist))
    }
}

public func build_octree(
    particles: [particle_t], masses: [Double], positions: [vector3_t]
) -> octree_node_t? {
    guard !particles.isEmpty else { return nil }
    var min_corner = positions[0]
    var max_corner = positions[0]
    for position in positions {
        min_corner = vector3_t(
            min(min_corner.x, position.x),
            min(min_corner.y, position.y),
            min(min_corner.z, position.z))
        max_corner = vector3_t(
            max(max_corner.x, position.x),
            max(max_corner.y, position.y),
            max(max_corner.z, position.z))
    }
    let center = (min_corner + max_corner) * 0.5
    var half_extent = max(
        max_corner.x - center.x, max(max_corner.y - center.y, max_corner.z - center.z))
    half_extent = max(half_extent, 1e-6) * 1.05
    let root = octree_node_t(center: center, half_extent: half_extent)
    for index in particles.indices {
        root.insert(
            particle_index: index, particles: particles,
            masses: masses, positions: positions)
    }
    root.summarize(masses: masses, positions: positions)
    return root
}
