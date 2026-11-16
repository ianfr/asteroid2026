# MicroBenchmarks

Run with `swift test --filter MicroBenchmarks` from the package root.

Each case compares a spatial structure against its naive reference on
the same deterministic particles, then requires the spatial version to
win on wall time:

- gravity: `compute_accelerations` with Barnes-Hut octree vs
  `compute_accelerations_brute` at 1000, 5000, 7500 and 10000 bodies,
  printing the speedup or slowdown per size. Agreement is worst
  per-particle relative error below 0.1 for `theta = 0.5`, and the
  test passes if any size shows a speedup.
- collision: `detect_collision_events` uniform hash grid vs an
  all-pairs loop over the same contact distance. Agreement is the exact
  same overlapping index-pair set.

Sizes stay small (10000 gravity bodies, 3000 collision bodies,
best of 3 repeats) and both inputs are fixed deterministic lattices,
so each case finishes in about a second or two.
Any correctness or speed failure fails the test.
