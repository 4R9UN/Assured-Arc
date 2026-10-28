#!/usr/bin/env python3
"""Render animated SVG documentation assets to optimized looping GIFs."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import argparse
import os
import subprocess
import tempfile
import re
from pathlib import Path
import xml.etree.ElementTree as ET

from PIL import Image

# Requires Pillow and a Playwright-managed Chromium headless shell.


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "docs" / "assets"
PLAYWRIGHT_ROOT = Path(os.environ["LOCALAPPDATA"]) / "ms-playwright"
ASSETS = {
    "assured-arc-architecture": (1280, 768, 4.0),
    "assured-arc-harness-architecture": (1280, 760, 4.0),
    "assured-arc-installation-flow": (1280, 720, 4.0),
}

SVG_NS = "http://www.w3.org/2000/svg"
TOKEN = re.compile(r"[MLHVCZmlhvcz]|-?\d+(?:\.\d+)?")


def _path_points(path: str) -> list[tuple[float, float]]:
    tokens = TOKEN.findall(path.replace(",", " "))
    points: list[tuple[float, float]] = []
    cursor = (0.0, 0.0)
    start = cursor
    command = ""
    index = 0

    def number() -> float:
        nonlocal index
        value = float(tokens[index])
        index += 1
        return value

    def point(relative: bool) -> tuple[float, float]:
        x, y = number(), number()
        return (cursor[0] + x, cursor[1] + y) if relative else (x, y)

    while index < len(tokens):
        if tokens[index].isalpha():
            command = tokens[index]
            index += 1
        relative = command.islower()
        operation = command.upper()
        if operation == "M":
            cursor = point(relative)
            start = cursor
            points.append(cursor)
            command = "l" if relative else "L"
        elif operation == "L":
            cursor = point(relative)
            points.append(cursor)
        elif operation == "H":
            x = number()
            cursor = (cursor[0] + x if relative else x, cursor[1])
            points.append(cursor)
        elif operation == "V":
            y = number()
            cursor = (cursor[0], cursor[1] + y if relative else y)
            points.append(cursor)
        elif operation == "C":
            origin = cursor
            control1 = point(relative)
            control2 = point(relative)
            destination = point(relative)
            for step in range(1, 25):
                t = step / 24
                inverse = 1 - t
                points.append(
                    (
                        inverse**3 * origin[0] + 3 * inverse**2 * t * control1[0] + 3 * inverse * t**2 * control2[0] + t**3 * destination[0],
                        inverse**3 * origin[1] + 3 * inverse**2 * t * control1[1] + 3 * inverse * t**2 * control2[1] + t**3 * destination[1],
                    )
                )
            cursor = destination
        elif operation == "Z":
            cursor = start
            points.append(cursor)
            command = ""
        else:
            raise ValueError(f"Unsupported SVG path command: {command}")
    if len(points) < 2:
        raise ValueError(f"Animation path has fewer than two points: {path}")
    return points


def _point_at(points: list[tuple[float, float]], progress: float) -> tuple[float, float]:
    lengths = [((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5 for (ax, ay), (bx, by) in zip(points, points[1:])]
    total = sum(lengths)
    target = (progress % 1.0) * total
    for index, length in enumerate(lengths):
        if target <= length:
            ax, ay = points[index]
            bx, by = points[index + 1]
            ratio = 0 if length == 0 else target / length
            return ax + (bx - ax) * ratio, ay + (by - ay) * ratio
        target -= length
    return points[-1]


def _seconds(value: str) -> float:
    return float(value.removesuffix("s") or 0)


def _translation(element: ET.Element, root: ET.Element) -> tuple[float, float]:
    parents = {child: parent for parent in root.iter() for child in parent}
    x = y = 0.0
    current: ET.Element | None = element
    while current is not None:
        transform = current.attrib.get("transform", "")
        match = re.fullmatch(r"\s*translate\(\s*(-?\d+(?:\.\d+)?)\s*(?:[, ]\s*(-?\d+(?:\.\d+)?))?\s*\)\s*", transform)
        if match:
            x += float(match.group(1))
            y += float(match.group(2) or 0)
        elif transform:
            raise ValueError(f"Unsupported ancestor transform: {transform}")
        current = parents.get(current)
    return x, y


def _browser() -> Path:
    candidates = sorted(PLAYWRIGHT_ROOT.glob("chromium_headless_shell-*/chrome-headless-shell-win64/chrome-headless-shell.exe"), reverse=True)
    if not candidates:
        raise FileNotFoundError("Playwright Chromium headless shell is not installed")
    return candidates[0]


def _render_frame(source: Path, target: Path, elapsed: float, width: int, height: int) -> None:
    tree = ET.parse(source)
    root = tree.getroot()
    for motion in list(root.iter(f"{{{SVG_NS}}}animateMotion")):
        parent = next(element for element in root.iter() if motion in list(element))
        duration = _seconds(motion.attrib.get("dur", "1s"))
        begin = _seconds(motion.attrib.get("begin", "0s"))
        path = motion.attrib.get("path", "")
        mpath = motion.find(f"{{{SVG_NS}}}mpath")
        if mpath is not None:
            reference = mpath.attrib.get("href", "").removeprefix("#")
            source_path = next((element for element in root.iter() if element.attrib.get("id") == reference), None)
            if source_path is None or "d" not in source_path.attrib:
                raise ValueError(f"Animation path reference not found: {reference}")
            if not source_path.attrib.get("data-motion-intent"):
                raise ValueError(f"Animation path has no semantic intent: {reference}")
            classes = set(source_path.attrib.get("class", "").split())
            if not classes.intersection({"flow", "flow-blue", "flow-rust", "route"}):
                raise ValueError(f"Animation path is not a visible causal connector: {reference}")
            path = source_path.attrib["d"]
        point = _point_at(_path_points(path), (elapsed - begin) / duration)
        if mpath is not None and source_path is not None:
            offset = _translation(source_path, root)
            point = point[0] + offset[0], point[1] + offset[1]
        parent.set("transform", f"translate({point[0]:.2f} {point[1]:.2f})")
        parent.remove(motion)
    staged = target.with_suffix(".svg")
    tree.write(staged, encoding="utf-8", xml_declaration=True)
    subprocess.run(
        [
            str(_browser()),
            "--headless",
            "--disable-gpu",
            "--hide-scrollbars",
            f"--window-size={width},{height}",
            f"--screenshot={target}",
            staged.resolve().as_uri(),
        ],
        check=True,
        capture_output=True,
    )


def capture(name: str, width: int, height: int, duration: float, fps: int) -> None:
    source = ASSET_DIR / f"{name}.svg"
    target = ASSET_DIR / f"{name}.gif"
    if not source.exists():
        raise FileNotFoundError(source)
    frame_count = max(2, round(duration * fps))
    frame_ms = round(1000 / fps)
    with tempfile.TemporaryDirectory(prefix=f"{name}-") as temporary:
        temp = Path(temporary)
        frame_paths = [temp / f"frame-{index:03d}.png" for index in range(frame_count)]
        with ThreadPoolExecutor(max_workers=min(8, os.cpu_count() or 4)) as pool:
            futures = [
                pool.submit(_render_frame, source, frame_paths[index], index / fps, width, height)
                for index in range(frame_count)
            ]
            for future in futures:
                future.result()
        rgb_frames = [Image.open(frame).convert("RGB") for frame in frame_paths]

        palette = rgb_frames[0].quantize(colors=128, method=Image.Quantize.FASTOCTREE)
        frames = [
            image.quantize(palette=palette, dither=Image.Dither.NONE)
            for image in rgb_frames
        ]

        frames[0].save(
            target,
            save_all=True,
            append_images=frames[1:],
            duration=frame_ms,
            loop=0,
            optimize=True,
            disposal=1,
        )
    print(f"Rendered {target.relative_to(ROOT)} ({frame_count} frames)")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("names", nargs="*", choices=sorted(ASSETS))
    parser.add_argument("--fps", type=int, default=8)
    args = parser.parse_args()
    names = args.names or list(ASSETS)
    for name in names:
        capture(name, *ASSETS[name], args.fps)


if __name__ == "__main__":
    main()
