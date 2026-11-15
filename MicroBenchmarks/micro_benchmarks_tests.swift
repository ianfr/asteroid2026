import Foundation
import Testing

@testable import asteroid2026

// Deterministic lattice placement from closed-form arithmetic only.
// lattice_unit returns the fractional part of index * multiplier, so the
// same index always yields the same coordinate with no generator state.
private func lattice_unit(index: Int, multiplier: Double) -> Double {
    return (Double(index) * multiplier).truncatingRemainder(dividingBy: 1.0)
}

private func make_gravity_benchmark_particles(count: Int) -> [particle_t] {
    var particles = [particle_t]()
    particles.reserveCapacity(count)
    for i in 0..<count {
        particles.append(
            particle_t(
                id: i, mass: 1e9 * (1.0 + 0.5 * Double(i % 7)), radius: 1,
                position: vector3_t(
                    lattice_unit(index: i, multiplier: 0.6180339887498949) * 200.0,
                    lattice_unit(index: i, multiplier: 0.4142135623730951) * 200.0,
                    lattice_unit(index: i, multiplier: 0.7320508075688772) * 200.0)))
    }
    return particles
}

private func make_collision_benchmark_particles(count: Int) -> [particle_t] {
    var particles = [particle_t]()
    particles.reserveCapacity(count)
    // Dense 3D lattice plus small deterministic offsets: neighbors overlap
    // often enough to exercise pair detection while staying sparse enough
    // for the hash grid to skip most pairs.
    let spacing = 2.5
    let side = Int(ceil(pow(Double(count), 1.0 / 3.0)))
    for i in 0..<count {
        let jx = (lattice_unit(index: i, multiplier: 0.6180339887498949) - 0.5)
            * spacing * 0.4
        let jy = (lattice_unit(index: i, multiplier: 0.4142135623730951) - 0.5)
            * spacing * 0.4
        let jz = (lattice_unit(index: i, multiplier: 0.7320508075688772) - 0.5)
            * spacing * 0.4
        particles.append(
            particle_t(
                id: i, mass: 1, radius: 1,
                position: vector3_t(
                    Double(i % side) * spacing + jx,
                    Double((i / side) % side) * spacing + jy,
                    Double(i / (side * side)) * spacing + jz)))
    }
    return particles
}

private func measure_seconds(repeats: Int, work: () -> Void) -> Double {
    work()
    var best = Double.greatestFiniteMagnitude
    for _ in 0..<repeats {
        let start = Date()
        work()
        best = min(best, Date().timeIntervalSince(start))
    }
    return best
}

private func naive_collision_pair_set(
    particles: [particle_t], separation_buffer: Double
) -> Set<Int64> {
    var found = Set<Int64>()
    for i in 0..<particles.count {
        for j in (i + 1)..<particles.count {
            let offset = particles[j].position - particles[i].position
            let contact =
                particles[i].radius + particles[j].radius + separation_buffer
            if offset.norm() <= contact {
                found.insert((Int64(i) << 32) | Int64(j))
            }
        }
    }
    return found
}

private func grid_collision_pair_set(
    particles: [particle_t], separation_buffer: Double
) -> Set<Int64> {
    var found = Set<Int64>()
    for event in detect_collision_events(
        particles: particles, separation_buffer: separation_buffer)
    {
        let low = Int64(min(event.index_a, event.index_b))
        let high = Int64(max(event.index_a, event.index_b))
        found.insert((low << 32) | high)
    }
    return found
}

@Test func micro_gravity_octree_beats_brute_and_agrees() {
    var config = simulation_config_t()
    config.use_barnes_hut = true
    config.barnes_hut_threshold = 64
    config.barnes_hut_theta = 0.5
    var any_speedup = false
    for count in [1000, 5000, 7500, 10000] {
        let particles = make_gravity_benchmark_particles(count: count)
        var fast_result = [vector3_t]()
        var slow_result = [vector3_t]()
        let fast_seconds = measure_seconds(repeats: 3) {
            fast_result = compute_accelerations(particles: particles, config: config)
        }
        let slow_seconds = measure_seconds(repeats: 3) {
            slow_result = compute_accelerations_brute(
                particles: particles,
                gravitational_constant: config.gravitational_constant,
                softening_length: config.softening_length)
        }
        var worst = 0.0
        for i in fast_result.indices {
            let scale = max(slow_result[i].norm(), 1e-12)
            worst = max(worst, (fast_result[i] - slow_result[i]).norm() / scale)
        }
        let speedup = slow_seconds / max(fast_seconds, 1e-9)
        let verdict = fast_seconds < slow_seconds ? "speedup" : "slowdown"
        print(
            "gravity n=\(count): octree \(String(format: "%.3f", fast_seconds))s vs brute "
                + "\(String(format: "%.3f", slow_seconds))s "
                + "x\(String(format: "%.2f", speedup)) \(verdict) "
                + "worst_relative_error \(String(format: "%.4f", worst))")
        #expect(worst < 0.1)
        #expect(fast_seconds < 2.0)
        #expect(slow_seconds < 2.0)
        any_speedup = any_speedup || fast_seconds < slow_seconds
    }
    #expect(any_speedup)
}

@Test func micro_collision_grid_beats_naive_and_agrees() {
    let buffer = 0.05
    let particles = make_collision_benchmark_particles(count: 3000)
    var grid_result = Set<Int64>()
    var naive_result = Set<Int64>()
    let grid_seconds = measure_seconds(repeats: 3) {
        grid_result = grid_collision_pair_set(
            particles: particles, separation_buffer: buffer)
    }
    let naive_seconds = measure_seconds(repeats: 3) {
        naive_result = naive_collision_pair_set(
            particles: particles, separation_buffer: buffer)
    }
    #expect(!grid_result.isEmpty)
    #expect(grid_result == naive_result)
    #expect(grid_seconds < naive_seconds)
    #expect(grid_seconds < 2.0)
    #expect(naive_seconds < 2.0)
}
