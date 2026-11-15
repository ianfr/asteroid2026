import numpy as np
import pandas as pd
import postprocess
import pytest
from PIL import Image

from postprocess import (
    frame_metrics,
    momentum_magnitudes,
    potential_energy_and_overlaps,
    radial_wave_rows,
    sized_glyph,
    write_wave_plots,
)


def make_frame(rows):
    return pd.DataFrame(
        rows,
        columns=[
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
        ],
    )


@pytest.mark.parametrize("existing_output", [False, True])
def test_cli_clears_output_before_writing(tmp_path, monkeypatch, existing_output):
    frame = make_frame([[0, 0, 0, 0, 0, 0, 1.0, 0.5, 0, 0, 0]])
    source = tmp_path / "ast.csv.0000000000"
    frame.to_csv(source, index=False)
    output = tmp_path / "plots"
    if existing_output:
        stale_frames = output / "animation_frames"
        stale_frames.mkdir(parents=True)
        (stale_frames / "frame_0000001000.png").write_text("stale")
        (output / "old_plot.png").write_text("stale")

    def check_output(table, seconds_per_frame, out_dir):
        assert sorted(path.name for path in output.iterdir()) == ["metrics.csv"]

    monkeypatch.setattr(postprocess, "write_plots", check_output)
    monkeypatch.setattr(postprocess, "write_wave_plots", lambda *args: None)
    postprocess.main([str(tmp_path), "--out", str(output), "--no-animation"])
    assert source.exists()
    assert len(pd.read_csv(output / "metrics.csv")) == 1


@pytest.mark.parametrize("destination", ["same", "ancestor", "symlink"])
def test_cli_rejects_output_that_would_delete_input(tmp_path, destination):
    source = tmp_path / "input"
    source.mkdir()
    marker = source / "keep.txt"
    marker.write_text("keep")
    output = source if destination == "same" else tmp_path
    if destination == "symlink":
        output = tmp_path / "alias"
        output.symlink_to(source, target_is_directory=True)
    with pytest.raises(SystemExit) as error:
        postprocess.main([str(source), "--out", str(output)])
    assert error.value.code == 2
    assert marker.read_text() == "keep"


def test_two_body_energy_matches_analytic():
    frame = make_frame(
        [
            [0, 0, 0, 1, 0, 0, 2.0, 0.5, 0, 0, 0],
            [4, 0, 0, 0, 2, 0, 3.0, 0.5, 1, 1, 1],
        ]
    )
    metrics = frame_metrics(frame, 1.0)
    assert metrics["kinetic"] == 0.5 * 2 * 1 + 0.5 * 3 * 4
    assert metrics["potential"] == -2.0 * 3.0 / 4.0
    assert metrics["overlaps"] == 0
    assert metrics["momentum"] == (2.0**2 + 6.0**2) ** 0.5


def test_touching_pair_counts_as_one_overlap():
    frame = make_frame(
        [
            [0, 0, 0, 0, 0, 0, 1.0, 1.0, 0, 0, 0],
            [1, 0, 0, 0, 0, 0, 1.0, 1.0, 1, 0, 0],
        ]
    )
    assert frame_metrics(frame, 1.0)["overlaps"] == 1


def test_chunked_pair_loop_matches_single_chunk():
    pos = [[float(i), 0.0, 0.0] for i in range(6)]
    mass = [1.0] * 6
    radius = [1.0] * 6
    import numpy as np

    full = potential_energy_and_overlaps(
        np.array(pos), np.array(mass), np.array(radius), 2.5, chunk=100
    )
    split = potential_energy_and_overlaps(
        np.array(pos), np.array(mass), np.array(radius), 2.5, chunk=1
    )
    assert full[1] == split[1]
    assert abs(full[0] - split[0]) < 1e-9 * abs(full[0])


def test_momentum_histogram_counts_cover_whole_asteroid():
    frame = make_frame(
        [
            [0, 0, 0, 1, 0, 0, 2.0, 0.5, 0, 0, 0],
            [4, 0, 0, 0, 2, 0, 3.0, 0.5, 1, 0, 0],
            [9, 0, 0, 0, 0, 3, 1.0, 0.5, 2, 1, 1],
        ]
    )
    edges = np.linspace(0, float(np.max(momentum_magnitudes(frame))) or 1.0, 11)
    for ast_id, expected in ((0, 2), (1, 1)):
        sub = frame[frame["ast_id"] == ast_id]
        counts, _ = np.histogram(momentum_magnitudes(sub), bins=edges)
        assert int(np.sum(counts)) == expected


def test_uniform_expansion_gives_flat_radial_profile():
    frame = make_frame(
        [
            [-5, 0, 0, -2, 0, 0, 1.0, 0.5, 0, 0, 0],
            [5, 0, 0, 2, 0, 0, 1.0, 0.5, 1, 0, 0],
        ]
    )
    means = radial_wave_rows(frame, 0, np.linspace(0, 6.0, 4))
    filled = means[~np.isnan(means)]
    assert len(filled) > 0
    assert np.allclose(filled, 2.0)


def test_sized_glyph_scales_with_radius():
    frame = make_frame(
        [
            [0, 0, 0, 0, 0, 0, 1.0, 1.0, 0, 0, 0],
            [10, 0, 0, 0, 0, 0, 1.0, 3.0, 1, 1, 1],
        ]
    )
    glyph = sized_glyph(frame)
    bounds = glyph.bounds
    assert abs(bounds[0] - (-1.0)) < 0.5
    assert abs(bounds[1] - 13.0) < 0.5


def test_wave_plots_write_one_file_per_asteroid(tmp_path):
    frame = make_frame(
        [
            [0, 0, 0, 1, 0, 0, 1.0, 0.5, 0, 0, 0],
            [5, 0, 0, -1, 0, 0, 1.0, 0.5, 1, 1, 1],
        ]
    )
    write_wave_plots([frame, frame], 1.0, str(tmp_path))
    for ast_id in (0, 1):
        assert (tmp_path / f"momentum_hist_ast{ast_id}.png").exists()
        assert (tmp_path / f"radial_wave_ast{ast_id}.png").exists()


def test_frame_sequence_loads_on_demand(monkeypatch):
    loaded = []

    def load(path):
        loaded.append(path)
        return path

    monkeypatch.setattr(postprocess, "load_frame", load)
    frames = postprocess.frame_sequence_t(["first.csv", "second.csv"])
    assert len(frames) == 2
    assert loaded == []
    assert list(frames) == ["first.csv", "second.csv"]
    assert list(frames) == ["first.csv", "second.csv"]
    assert loaded == ["first.csv", "second.csv"] * 2


def test_gif_streams_pngs_with_timing_and_independent_palettes(tmp_path):
    colors = [(255, 0, 0), (0, 255, 0), (0, 0, 255)]
    gif_path = tmp_path / "animation.gif"

    def paths():
        for number, color in enumerate(colors):
            if number:
                # Data must reach disk before requesting the next frame.
                assert gif_path.stat().st_size > 0
            path = tmp_path / f"{number}.png"
            with Image.new("RGB", (128, 128), color) as image:
                image.save(path)
            yield path

    postprocess.write_gif(paths(), gif_path, fps=5)
    with Image.open(gif_path) as gif:
        assert gif.n_frames == len(colors)
        assert gif.info["loop"] == 0
        for number, color in enumerate(colors):
            gif.seek(number)
            assert gif.info["duration"] == 200
            assert gif.convert("RGB").getpixel((0, 0)) == color


def test_animation_fallback_saves_pngs_and_gif_only(tmp_path, monkeypatch):
    frame = make_frame(
        [
            [0, 0, 0, 1, 0, 0, 1.0, 0.5, 0, 0, 0],
            [5, 0, 0, -1, 0, 0, 1.0, 0.5, 1, 1, 1],
        ]
    )
    moved = frame.copy()
    moved["rx"] += 2
    csv_paths = [tmp_path / f"ast.csv.{number}" for number in range(2)]
    for path, data in zip(csv_paths, [frame, moved]):
        data.to_csv(path, index=False)

    def fail_render(*args):
        raise RuntimeError("headless GL unavailable")

    monkeypatch.setattr(postprocess, "render_animation_pyvista", fail_render)
    frames = postprocess.frame_sequence_t(csv_paths)
    lo, hi = postprocess.animation_bounds(frames, view_percent=100)
    np.testing.assert_allclose(lo, [0, 0, 0])
    np.testing.assert_allclose(hi, [7, 0, 0])
    postprocess.write_animation(frames, str(tmp_path), fps=5)
    pngs = sorted((tmp_path / "animation_frames").glob("*.png"))
    assert [path.name for path in pngs] == [
        "frame_0000000000.png",
        "frame_0000000001.png",
    ]
    with Image.open(tmp_path / "animation.gif") as gif:
        assert gif.n_frames == 2
        for path in pngs:
            with Image.open(path) as png:
                assert png.format == "PNG"
                assert png.size == gif.size
    assert not list(tmp_path.glob("*.mp4"))


def test_pyvista_saves_screenshots_without_retaining_images(tmp_path, monkeypatch):
    import pyvista as pv
    from types import SimpleNamespace

    frame = make_frame([[0, 0, 0, 0, 0, 0, 1.0, 0.5, 0, 0, 0]])
    screenshots = []
    camera_views = []
    closed = []

    class plotter_t:
        def __init__(self, **kwargs):
            self.camera = SimpleNamespace()

        def add_mesh(self, *args, **kwargs):
            assert kwargs["reset_camera"] is False
            return object()

        def remove_actor(self, actor):
            pass

        def render(self):
            pass

        def screenshot(self, path, return_img):
            assert return_img is False
            camera_views.append(vars(self.camera).copy())
            with Image.new("RGB", (16, 16)) as image:
                image.save(path)
            screenshots.append(path)

        def close(self):
            closed.append(True)

    monkeypatch.setattr(pv, "Plotter", plotter_t)
    monkeypatch.setattr(postprocess, "sized_glyph", lambda frame: object())
    moved = frame.copy()
    moved["rx"] += 4
    paths = postprocess._pyvista_shots([frame, moved], str(tmp_path))
    assert paths == screenshots
    assert len(paths) == 2
    assert all(isinstance(path, str) for path in paths)
    assert closed == [True]
    assert camera_views[0] == camera_views[1]
    assert camera_views[0]["focal_point"] == (2.0, 0.0, 0.0)


def test_animation_bounds_trim_outliers_and_cover_motion():
    frame = make_frame(
        [
            [x, 0, 0, 0, 0, 0, 1.0, 0.5, i, 0, 0]
            for i, x in enumerate([-1000, *range(9), 1000])
        ]
    )
    moved = frame.copy()
    moved["rx"] += 10
    frames = [frame, moved]
    lo, hi = postprocess.animation_bounds(frames)
    np.testing.assert_allclose(lo, [0, 0, 0])
    np.testing.assert_allclose(hi, [18, 0, 0])
    lo, hi = postprocess.animation_bounds(frames, view_percent=100)
    np.testing.assert_allclose(lo, [-1000, 0, 0])
    np.testing.assert_allclose(hi, [1010, 0, 0])
    lo, hi = postprocess.animation_bounds(frames, view_percent=50)
    np.testing.assert_allclose(lo, [1.5, 0, 0])
    np.testing.assert_allclose(hi, [16.5, 0, 0])


@pytest.mark.parametrize("value", ["0", "-1", "101", "nan", "inf"])
def test_view_percent_rejects_invalid_values(value, capsys):
    with pytest.raises(SystemExit) as error:
        postprocess.main(["unused", f"--view-percent={value}"])
    assert error.value.code == 2
    assert "--view-percent must be" in capsys.readouterr().err


@pytest.mark.parametrize(
    "options, expected", [([], 80.0), (["--view-percent", "95"], 95.0)]
)
def test_cli_passes_view_percent_to_animation(tmp_path, monkeypatch, options, expected):
    frame = make_frame([[0, 0, 0, 0, 0, 0, 1.0, 0.5, 0, 0, 0]])
    frame.to_csv(tmp_path / "ast.csv.0000000000", index=False)
    monkeypatch.setattr(postprocess, "write_plots", lambda *args: None)
    monkeypatch.setattr(postprocess, "write_wave_plots", lambda *args: None)
    percentages = []
    monkeypatch.setattr(
        postprocess,
        "write_animation",
        lambda frames, out_dir, fps, view_percent: percentages.append(view_percent),
    )
    postprocess.main([str(tmp_path), "--out", str(tmp_path / "plots"), *options])
    assert percentages == [expected]


def test_matplotlib_keeps_percentile_limits_fixed(tmp_path, monkeypatch):
    frame = make_frame(
        [
            [x, 0, 0, 0, 0, 0, 1.0, 0.5, i, 0, 0]
            for i, x in enumerate([-1000, *range(9), 1000])
        ]
    )
    moved = frame.copy()
    moved["rx"] += 10
    views = []

    def savefig(figure, path, **kwargs):
        ax = figure.axes[0]
        views.append((ax.get_xlim(), ax.get_ylim(), ax.get_zlim(), ax.elev, ax.azim))

    monkeypatch.setattr(postprocess.plt.Figure, "savefig", savefig)
    postprocess.render_animation_matplotlib([frame, moved], str(tmp_path), fps=5)
    assert views[0] == views[1]
    np.testing.assert_allclose(views[0][0], [-0.9, 18.9])
