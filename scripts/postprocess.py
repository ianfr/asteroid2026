"""Post-process asteroid2026 CSV frames into metrics, plots, and an animation.

Reads per-frame files (ast.csv.NNNNNNNNNN) written by the simulator and emits,
into the output directory:
  metrics.csv          per-frame kinetic/potential/total energy, momentum,
                       center of mass, max speed, overlap count
  energy_over_time.png kinetic, potential, and total energy vs frame
  collision_rate.png   overlapping-pair count per frame (and per unit time)
  kinematics.png       max speed, momentum drift, center-of-mass drift
  animation.gif       pyvista point animation colored by body (ast_id)
  animation_frames/   numbered PNGs used to create the GIF

Overlap count is the in-data proxy for the collision rate: pairs whose
separation is smaller than the sum of their radii.
"""

import argparse
import glob
import os
import shutil
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

EXPECTED_COLUMNS = [
    "rx",
    "ry",
    "rz",
    "vx",
    "vy",
    "vz",
    "mass",
    "radius",
    "id",
    "ast_id",
    "col_ast",
]


def find_frames(input_dir):
    paths = sorted(glob.glob(os.path.join(input_dir, "ast.csv.*")))
    if not paths:
        raise SystemExit(f"no ast.csv.* frames found in {input_dir}")
    return paths


def load_frame(path):
    frame = pd.read_csv(path)
    missing = [c for c in EXPECTED_COLUMNS if c not in frame.columns]
    if missing:
        raise SystemExit(f"{path}: missing columns {missing}")
    return frame


class frame_sequence_t:
    """Reload CSVs on demand instead of retaining the entire simulation."""

    def __init__(self, paths):
        self.paths = paths

    def __len__(self):
        return len(self.paths)

    def __getitem__(self, index):
        return load_frame(self.paths[index])


def potential_energy_and_overlaps(pos, mass, radius, grav_g, chunk=512):
    """Total gravitational PE and overlapping-pair count, in bounded tiles."""
    count = len(pos)
    pot = 0.0
    overlaps = 0
    for start in range(0, count, chunk):
        stop = min(start + chunk, count)
        rows = np.arange(start, stop)[:, None]
        for col_start in range(start, count, chunk):
            col_stop = min(col_start + chunk, count)
            cols = np.arange(col_start, col_stop)
            diff = pos[start:stop, None, :] - pos[None, col_start:col_stop, :]
            dist = np.linalg.norm(diff, axis=-1)
            mask = (cols[None, :] > rows) & (dist > 0)
            inv = np.zeros_like(dist)
            np.divide(1.0, dist, out=inv, where=mask)
            pot -= grav_g * float(
                np.sum(mass[start:stop, None] * mass[None, col_start:col_stop] * inv)
            )
            contact = radius[start:stop, None] + radius[None, col_start:col_stop]
            overlaps += int(np.sum(mask & (dist < contact)))
    return pot, overlaps


def frame_metrics(frame, grav_g):
    pos = frame[["rx", "ry", "rz"]].to_numpy(dtype=float)
    vel = frame[["vx", "vy", "vz"]].to_numpy(dtype=float)
    mass = frame["mass"].to_numpy(dtype=float)
    radius = frame["radius"].to_numpy(dtype=float)
    speed_sq = np.sum(vel * vel, axis=1)
    kin = float(0.5 * np.sum(mass * speed_sq))
    pot, overlaps = potential_energy_and_overlaps(pos, mass, radius, grav_g)
    momentum = mass[:, None] * vel
    total_mass = float(np.sum(mass))
    center = np.sum(mass[:, None] * pos, axis=0) / total_mass
    return {
        "n_particles": len(frame),
        "kinetic": kin,
        "potential": pot,
        "total_energy": kin + pot,
        "momentum": float(np.linalg.norm(np.sum(momentum, axis=0))),
        "com_x": float(center[0]),
        "com_y": float(center[1]),
        "com_z": float(center[2]),
        "max_speed": float(np.sqrt(np.max(speed_sq))) if len(frame) else 0.0,
        "overlaps": overlaps,
    }


def write_plots(table, seconds_per_frame, out_dir):
    frame_no = table["frame"].to_numpy()
    time = frame_no * seconds_per_frame

    fig, (top, bottom) = plt.subplots(2, 1, figsize=(9, 7), sharex=True)
    top.plot(time, table["kinetic"], label="kinetic")
    top.plot(time, table["total_energy"], label="total")
    top.set_ylabel("energy (J)")
    top.legend()
    top.set_title("Energy over time")
    bottom.plot(time, table["potential"], label="potential", color="C1")
    bottom.set_xlabel("time (s)")
    bottom.set_ylabel("energy (J)")
    bottom.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(out_dir, "energy_over_time.png"), dpi=120)
    plt.close(fig)

    fig, left = plt.subplots(figsize=(9, 4))
    left.bar(time, table["overlaps"], width=0.8 * seconds_per_frame, color="C3")
    left.set_xlabel("time (s)")
    left.set_ylabel("overlapping pairs per frame")
    right = left.twinx()
    right.plot(time, table["overlaps"] / seconds_per_frame, color="C0")
    right.set_ylabel("collision rate (pairs/s)")
    left.set_title("Collision rate proxy (overlapping pairs)")
    fig.tight_layout()
    fig.savefig(os.path.join(out_dir, "collision_rate.png"), dpi=120)
    plt.close(fig)

    com = table[["com_x", "com_y", "com_z"]].to_numpy()
    drift = np.linalg.norm(com - com[0], axis=1)
    fig, (top, bottom) = plt.subplots(2, 1, figsize=(9, 7), sharex=True)
    top.plot(time, table["max_speed"], color="C2")
    top.set_ylabel("max speed (m/s)")
    top.set_title("Kinematics")
    bottom.plot(time, table["momentum"], label="|p|", color="C4")
    bottom.plot(time, drift, label="com drift (m)", color="C5")
    bottom.set_xlabel("time (s)")
    bottom.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(out_dir, "kinematics.png"), dpi=120)
    plt.close(fig)


def momentum_magnitudes(frame):
    vel = frame[["vx", "vy", "vz"]].to_numpy(dtype=float)
    return frame["mass"].to_numpy(dtype=float) * np.linalg.norm(vel, axis=1)


def radial_wave_rows(frame, ast_id, edges):
    """Mean radial velocity per radius bin around the asteroid COM."""
    sub = frame[frame["ast_id"] == ast_id]
    pos = sub[["rx", "ry", "rz"]].to_numpy(dtype=float)
    vel = sub[["vx", "vy", "vz"]].to_numpy(dtype=float)
    mass = sub["mass"].to_numpy(dtype=float)
    if len(sub) == 0:
        return np.full(len(edges) - 1, np.nan)
    center = np.sum(mass[:, None] * pos, axis=0) / np.sum(mass)
    rel = pos - center
    dist = np.linalg.norm(rel, axis=1)
    with np.errstate(divide="ignore", invalid="ignore"):
        unit = np.where(
            dist[:, None] > 0,
            rel / np.where(dist[:, None] > 0, dist[:, None], 1.0),
            0.0,
        )
    radial = np.sum(vel * unit, axis=1)
    means = np.full(len(edges) - 1, np.nan)
    last = len(edges) - 2
    for b in range(len(edges) - 1):
        if b == last:
            in_bin = (dist >= edges[b]) & (dist <= edges[b + 1])
        else:
            in_bin = (dist >= edges[b]) & (dist < edges[b + 1])
        if np.any(in_bin):
            means[b] = float(np.mean(radial[in_bin]))
    return means


def write_wave_plots(
    frames, seconds_per_frame, out_dir, momentum_bins=40, radial_bins=24
):
    time = (np.arange(len(frames) + 1) - 0.5) * seconds_per_frame
    ast_ids = sorted({int(a) for frame in frames for a in frame["ast_id"].unique()})
    momentum_max = max(float(np.max(momentum_magnitudes(f))) for f in frames)
    momentum_edges = np.linspace(0, momentum_max or 1.0, momentum_bins + 1)
    for ast_id in ast_ids:
        heat = np.zeros((len(frames), momentum_bins), dtype=int)
        for row, frame in enumerate(frames):
            sub = frame[frame["ast_id"] == ast_id]
            if len(sub):
                heat[row], _ = np.histogram(
                    momentum_magnitudes(sub), bins=momentum_edges
                )
        fig, ax = plt.subplots(figsize=(9, 5))
        mesh = ax.pcolormesh(
            time, momentum_edges, heat.T, shading="auto", cmap="viridis"
        )
        fig.colorbar(mesh, ax=ax, label="particles")
        ax.set_xlabel("time (s)")
        ax.set_ylabel("momentum magnitude (kg m/s)")
        ax.set_title(f"Momentum histogram over time (asteroid {ast_id})")
        fig.tight_layout()
        fig.savefig(os.path.join(out_dir, f"momentum_hist_ast{ast_id}.png"), dpi=120)
        plt.close(fig)

        radii_max = 0.0
        for frame in frames:
            sub = frame[frame["ast_id"] == ast_id]
            if len(sub) == 0:
                continue
            pos = sub[["rx", "ry", "rz"]].to_numpy(dtype=float)
            mass = sub["mass"].to_numpy(dtype=float)
            center = np.sum(mass[:, None] * pos, axis=0) / np.sum(mass)
            radii_max = max(
                radii_max, float(np.max(np.linalg.norm(pos - center, axis=1)))
            )
        radial_edges = np.linspace(0, radii_max or 1.0, radial_bins + 1)
        wave = np.array([radial_wave_rows(f, ast_id, radial_edges) for f in frames])
        peak = np.nanmax(np.abs(wave)) if np.any(~np.isnan(wave)) else 0.0
        capped = peak or 1.0
        fig, ax = plt.subplots(figsize=(9, 5))
        mesh = ax.pcolormesh(
            time,
            radial_edges,
            wave.T,
            shading="auto",
            cmap="RdBu",
            vmin=-capped,
            vmax=capped,
        )
        fig.colorbar(mesh, ax=ax, label="mean radial velocity (m/s)")
        ax.set_xlabel("time (s)")
        ax.set_ylabel("distance from body center (m)")
        ax.set_title(f"Radial momentum wave (asteroid {ast_id})")
        fig.tight_layout()
        fig.savefig(os.path.join(out_dir, f"radial_wave_ast{ast_id}.png"), dpi=120)
        plt.close(fig)


def ensure_xvfb_on_path():
    """Expose the conda-packaged Xvfb binary, which lives outside bin/."""
    if os.environ.get("DISPLAY") or shutil.which("Xvfb"):
        return
    matches = glob.glob(os.path.join(sys.prefix, "*", "sysroot", "usr", "bin", "Xvfb"))
    if matches:
        os.environ["PATH"] = (
            os.path.dirname(matches[0]) + os.pathsep + os.environ.get("PATH", "")
        )


def animation_bounds(frames, view_percent=80.0):
    """Combine central per-axis percentile bounds across frames for one fixed view."""
    if not 0 < view_percent <= 100:
        raise ValueError("view percentage must be greater than 0 and at most 100")
    tail = (100.0 - view_percent) / 200.0
    lo = np.full(3, np.inf)
    hi = np.full(3, -np.inf)
    for frame in frames:
        pos = frame[["rx", "ry", "rz"]].to_numpy()
        frame_lo, frame_hi = np.quantile(pos, [tail, 1.0 - tail], axis=0)
        lo = np.minimum(lo, frame_lo)
        hi = np.maximum(hi, frame_hi)
    return lo, hi


def render_animation_pyvista(frames, out_dir, fps, view_percent=80.0):
    """Render point animation with pyvista; raises if headless GL fails."""
    try:
        return _pyvista_shots(frames, out_dir, view_percent)
    except Exception as direct_exc:
        if os.environ.get("DISPLAY"):
            raise
        ensure_xvfb_on_path()
        from xvfbwrapper import Xvfb

        display = Xvfb(width=1280, height=800)
        try:
            display.start()
            return _pyvista_shots(frames, out_dir, view_percent)
        except Exception:
            raise direct_exc
        finally:
            display.stop()


def _pyvista_shots(frames, out_dir, view_percent=80.0):
    import pyvista as pv

    pv.OFF_SCREEN = True
    plotter = None
    try:
        lo, hi = animation_bounds(frames, view_percent)
        center = (lo + hi) / 2
        extent = float(np.max(hi - lo)) or 1.0
        plotter = pv.Plotter(off_screen=True, window_size=(1280, 800))
        actor = plotter.add_mesh(
            sized_glyph(frames[0]),
            scalars="body",
            cmap="tab10",
            show_scalar_bar=True,
            reset_camera=False,
        )
        plotter.camera.position = (
            float(center[0]),
            float(center[1]),
            float(center[2] + 1.8 * extent),
        )
        plotter.camera.focal_point = (
            float(center[0]),
            float(center[1]),
            float(center[2]),
        )
        plotter.camera.up = (0.0, 1.0, 0.0)
        shots = []
        for number, frame in enumerate(frames):
            if number > 0:
                plotter.remove_actor(actor)
                actor = plotter.add_mesh(
                    sized_glyph(frame),
                    scalars="body",
                    cmap="tab10",
                    show_scalar_bar=False,
                    reset_camera=False,
                )
            plotter.render()
            path = os.path.join(out_dir, f"frame_{number:010d}.png")
            plotter.screenshot(path, return_img=False)
            shots.append(path)
        return shots
    finally:
        if plotter is not None:
            plotter.close()


def sized_glyph(frame):
    """Sphere glyphs scaled to each particle's true radius."""
    import pyvista as pv

    cloud = pv.PolyData(frame[["rx", "ry", "rz"]].to_numpy())
    cloud["body"] = frame["ast_id"].to_numpy()
    cloud["diameter"] = 2.0 * frame["radius"].to_numpy(dtype=float)
    return cloud.glyph(
        geom=pv.Sphere(theta_resolution=10, phi_resolution=10),
        scale="diameter",
        orient=False,
    )


def render_animation_matplotlib(frames, out_dir, fps, view_percent=80.0):
    from mpl_toolkits.mplot3d import Axes3D  # noqa: F401 (registers 3d)

    lo, hi = animation_bounds(frames, view_percent)
    pad = 0.05 * (float(np.max(hi - lo)) or 1.0)
    shots = []
    for number, frame in enumerate(frames):
        fig = plt.figure(figsize=(12.8, 8))
        ax = fig.add_subplot(111, projection="3d")
        pos = frame[["rx", "ry", "rz"]].to_numpy()
        radii = frame["radius"].to_numpy(dtype=float)
        span = float(np.max(radii) - np.min(radii))
        sizes = (
            np.full(len(frame), 4.0)
            if span <= 0
            else 4.0 + 96.0 * (radii - np.min(radii)) / span
        )
        ax.scatter(
            pos[:, 0],
            pos[:, 1],
            pos[:, 2],
            c=frame["ast_id"].to_numpy(),
            cmap="tab10",
            s=sizes,
        )
        ax.set_xlim(lo[0] - pad, hi[0] + pad)
        ax.set_ylim(lo[1] - pad, hi[1] + pad)
        ax.set_zlim(lo[2] - pad, hi[2] + pad)
        path = os.path.join(out_dir, f"frame_{number:010d}.png")
        fig.savefig(path, dpi=100)
        shots.append(path)
        plt.close(fig)
    return shots


def write_gif(paths, gif_path, fps):
    from PIL import Image, GifImagePlugin

    # Encode one frame at a time; Pillow's save_all buffers the full animation.
    with open(gif_path, "wb") as output:
        for number, path in enumerate(paths):
            with Image.open(path) as png:
                with png.convert("RGB") as rgb, rgb.quantize(colors=256) as frame:
                    if number == 0:
                        output.writelines(
                            GifImagePlugin.getheader(frame, info={"loop": 0})[0]
                        )
                    output.writelines(
                        GifImagePlugin.getdata(
                            frame,
                            duration=1000.0 / fps,
                            disposal=2,
                            include_color_table=number > 0,
                        )
                    )
                    output.flush()
        output.write(b";")


def write_animation(frames, out_dir, fps, view_percent=80.0):
    frames_dir = os.path.join(out_dir, "animation_frames")
    os.makedirs(frames_dir, exist_ok=True)
    try:
        shots = render_animation_pyvista(frames, frames_dir, fps, view_percent)
        engine = "pyvista"
    except Exception as exc:
        print(f"pyvista render failed ({exc}); using matplotlib fallback")
        shots = render_animation_matplotlib(frames, frames_dir, fps, view_percent)
        engine = "matplotlib"
    gif_path = os.path.join(out_dir, "animation.gif")
    write_gif(shots, gif_path, fps)
    print(f"animation via {engine}: {gif_path}; PNG frames: {frames_dir}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_dir", help="directory with ast.csv.* frames")
    parser.add_argument("--out", default="plots", help="output directory")
    parser.add_argument(
        "--grav-g",
        type=float,
        default=6.67430e-11,
        help="gravitational constant used by the simulation",
    )
    parser.add_argument(
        "--seconds-per-frame",
        type=float,
        default=1.0,
        help="simulated seconds between frames",
    )
    parser.add_argument("--stride", type=int, default=1, help="use every Nth frame")
    parser.add_argument("--max-frames", type=int, default=None)
    parser.add_argument("--fps", type=int, default=5)
    parser.add_argument(
        "--view-percent",
        type=float,
        default=80.0,
        help="central percentage per coordinate in each frame used for one fixed camera "
        "(default: 80; 100 includes all positions)",
    )
    parser.add_argument("--no-animation", action="store_true")
    args = parser.parse_args(argv)
    if not 0 < args.view_percent <= 100:
        parser.error("--view-percent must be greater than 0 and at most 100")
    input_directory = os.path.realpath(args.input_dir)
    output_directory = os.path.realpath(args.out)
    if os.path.commonpath([input_directory, output_directory]) == output_directory:
        parser.error("output directory must not contain or equal the input directory")

    paths = find_frames(args.input_dir)[:: args.stride]
    if args.max_frames is not None:
        paths = paths[: args.max_frames]
    # Remove old plots and animation frames, including those a shorter run won't replace.
    if os.path.exists(args.out):
        shutil.rmtree(args.out)
    os.makedirs(args.out, exist_ok=True)

    frames = frame_sequence_t(paths)
    rows = []
    for number, (path, frame) in enumerate(zip(paths, frames)):
        row = {"frame": number, "file": os.path.basename(path)}
        row.update(frame_metrics(frame, args.grav_g))
        rows.append(row)
    table = pd.DataFrame(rows)
    table.to_csv(os.path.join(args.out, "metrics.csv"), index=False)
    write_plots(table, args.seconds_per_frame, args.out)
    write_wave_plots(frames, args.seconds_per_frame, args.out)
    if not args.no_animation:
        write_animation(frames, args.out, args.fps, args.view_percent)
    print(
        f"frames: {len(frames)}, mean overlaps: {table['overlaps'].mean():.1f}, "
        f"energy drift: {table['total_energy'].iloc[-1] - table['total_energy'].iloc[0]:.3g} J"
    )
    print(
        f"wrote {args.out}/metrics.csv + plots"
        + ("" if args.no_animation else " + animation")
    )


if __name__ == "__main__":
    sys.exit(main())
