import Foundation
import asteroid2026

// Calibrates the spring cohesion model at Bennu particle scales with three
// particles. Background:
// - van der Waals cohesion rivals particle weight on small bodies
//   (Scheeres et al., Icarus 210, 2010; arXiv:1002.2478).
// - rubble piles carry tens of Pa of bulk cohesion: 1950 DA needs 44-76 Pa
//   (Rozitis et al., Nature 512, 2014).
// - fines act as cement in a constant-strength model (Sanchez & Scheeres,
//   Meteorit. Planet. Sci. 49, 2014).
// - Bennu mass 7.329e10 kg (Lauretta et al., Nature 568, 2019) gives
//   escape velocity ~0.2 m/s and surface gravity ~8e-5 m/s^2.
// Usage: swift run Examples cohesion
public func run_cohesion_calibration() {
    let bulk_density = 1190.0
    let particle_radius = 10.0
    let particle_mass =
        bulk_density * 4.0 / 3.0 * Double.pi * pow(particle_radius, 3)
    let big_g = 6.67430e-11
    let surface_gravity = big_g * 7.329e10 / (245.0 * 245.0)
    let calibrated = calibrated_cohesion_config(
        particle_mass: particle_mass, particle_radius: particle_radius,
        surface_gravity: surface_gravity,
        hold_speed: 0.2, break_speed: 1.0, overlap_fraction: 0.01)
    print("mass per particle: \(particle_mass) kg")
    print("surface gravity: \(surface_gravity) m/s^2")
    print(
        "calibrated connect/break: \(calibrated.connect_momentum) / "
            + "\(calibrated.break_momentum) kg m/s")
    print(
        "calibrated stiffness/damping: \(calibrated.spring_stiffness) N/m / "
            + "\(calibrated.spring_damping) N s/m")
    let resting_overlap =
        particle_mass * surface_gravity / calibrated.spring_stiffness
    print("resting overlap: \(resting_overlap) m")
    var default_config = cohesion_config_t()
    default_config.model = .spring
    for speed in [0.05, 0.1, 0.2, 0.5, 1.0, 2.0] {
        let pair = [
            particle_t(
                id: 0, mass: particle_mass, radius: particle_radius,
                position: vector3_t(0, 0, 0),
                velocity: vector3_t(-speed / 2.0, 0, 0)),
            particle_t(
                id: 1, mass: particle_mass, radius: particle_radius,
                position: vector3_t(2 * particle_radius, 0, 0),
                velocity: vector3_t(speed / 2.0, 0, 0)),
        ]
        var default_state = cohesion_state_t()
        update_cohesion_bonds(
            particles: pair, state: &default_state, config: default_config)
        var tuned_state = cohesion_state_t()
        update_cohesion_bonds(
            particles: pair, state: &tuned_state, config: calibrated)
        print(
            "approach \(speed) m/s: default bond \(!default_state.bonds.isEmpty), "
                + "calibrated bond \(!tuned_state.bonds.isEmpty)")
    }
}
