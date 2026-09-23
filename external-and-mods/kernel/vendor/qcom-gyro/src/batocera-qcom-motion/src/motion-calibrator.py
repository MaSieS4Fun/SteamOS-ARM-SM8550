#!/usr/bin/env python3
"""Controller-friendly AYN Odin 2 / Thor motion calibration UI.

SPDX-License-Identifier: GPL-3.0-or-later
"""

from __future__ import annotations

import atexit
import configparser
import math
import os
from pathlib import Path
import random
import re
import socket
import struct
import subprocess
import time
import zlib

import pyxel


def detect_profile() -> str:
    requested = os.environ.get("QCOM_MOTION_PROFILE", "auto")
    if requested != "auto":
        return requested
    try:
        compatible = Path("/proc/device-tree/compatible").read_bytes().split(b"\0")
    except OSError:
        compatible = []
    if b"ayn,thor" in compatible:
        return "thor"
    if b"ayn,odin2" in compatible:
        return "odin2"
    return "thor"


PROFILE = detect_profile()
IS_THOR = PROFILE == "thor"
DEVICE_NAME = "AYN Thor" if IS_THOR else "AYN Odin 2"
DEVICE_WORD = "BASE" if IS_THOR else "DEVICE"
TOP_WORD = "TOP / HINGE" if IS_THOR else "TOP"
BOTTOM_WORD = "BOTTOM / FRONT" if IS_THOR else "BOTTOM"

BRIDGE = Path(os.environ.get("QCOM_MOTION_BRIDGE", "/usr/bin/qcom-motion"))
SERVICE = Path(os.environ.get("QCOM_MOTION_SERVICE", "/usr/lib/systemd/system/qcom-motion.service"))
CALIBRATION_FILE = Path(
    os.environ.get(
        "QCOM_MOTION_CALIBRATION_FILE",
        f"/userdata/system/qcom-sensors/{PROFILE}/motion-calibration.ini",
    )
)
CALIBRATION_SAMPLES = 128
POSE_SAMPLES = 64
DSU_HOST = os.environ.get("QCOM_MOTION_DSU_HOST", "127.0.0.1")
DSU_PORT = int(os.environ.get("QCOM_MOTION_DSU_PORT", "26760"))
ACCEL_CALIBRATION_FRAME = "thor-dsu-v3" if IS_THOR else "odin2-dsu-v3"

POSES = (
    ("face_up", f"{DEVICE_WORD} FLAT - CONTROLS UP", (0.0, -1.0, 0.0)),
    ("left", f"{DEVICE_WORD.title()} on LEFT edge", (1.0, 0.0, 0.0)),
    ("right", f"{DEVICE_WORD.title()} on RIGHT edge", (-1.0, 0.0, 0.0)),
    ("top", f"{DEVICE_WORD.title()} on {TOP_WORD} edge", (0.0, 0.0, 1.0)),
    ("bottom", f"{DEVICE_WORD.title()} on {BOTTOM_WORD} edge", (0.0, 0.0, -1.0)),
)

POSE_PROMPTS = {
    "face_up": f"Lay {DEVICE_WORD} flat with controls up; capture starts automatically",
    "left": f"Hold {DEVICE_WORD} on LEFT edge; capture starts automatically",
    "right": f"Hold {DEVICE_WORD} on RIGHT edge; capture starts automatically",
    "top": f"Hold {DEVICE_WORD} on {TOP_WORD} edge; capture starts automatically",
    "bottom": f"Hold {DEVICE_WORD} on {BOTTOM_WORD} edge; capture starts automatically",
}


class DsuClient:
    def __init__(self) -> None:
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.setblocking(False)
        self.socket.connect((DSU_HOST, DSU_PORT))
        self.client_id = random.getrandbits(32)
        self.last_registration = 0.0

    def close(self) -> None:
        self.socket.close()

    def _packet(self, message_type: int, payload: bytes) -> bytes:
        packet = bytearray(
            struct.pack(
                "<4sHHIII",
                b"DSUC",
                1001,
                len(payload) + 4,
                0,
                self.client_id,
                message_type,
            )
            + payload
        )
        struct.pack_into("<I", packet, 8, zlib.crc32(packet))
        return bytes(packet)

    def update(self) -> list[tuple[tuple[float, float, float], tuple[float, float, float]]]:
        now = time.monotonic()
        if now - self.last_registration >= 1.0:
            payload = struct.pack("<BB6s", 1, 0, bytes(6))
            try:
                self.socket.send(self._packet(0x100002, payload))
            except OSError:
                pass
            self.last_registration = now

        samples = []
        while True:
            try:
                packet = self.socket.recv(256)
            except BlockingIOError:
                break
            except OSError:
                break
            if len(packet) < 100 or packet[:4] != b"DSUS":
                continue
            if struct.unpack_from("<I", packet, 16)[0] != 0x100002:
                continue
            accel = struct.unpack_from("<fff", packet, 76)
            dsu_gyro = struct.unpack_from("<fff", packet, 88)
            # Present angular velocity in the same physical XYZ frame as the
            # accelerometer and pose diagrams. DSU roll remains inverted.
            gyro = (dsu_gyro[0], dsu_gyro[1], -dsu_gyro[2])
            samples.append((accel, gyro))
        return samples


def run_service(action: str) -> None:
    if SERVICE.is_file():
        subprocess.run(
            [str(SERVICE), action],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.STDOUT,
        )


def read_config() -> configparser.ConfigParser:
    parser = configparser.ConfigParser()
    if CALIBRATION_FILE.is_file():
        parser.read(CALIBRATION_FILE)
    return parser


def write_config(parser: configparser.ConfigParser) -> None:
    CALIBRATION_FILE.parent.mkdir(parents=True, exist_ok=True)
    temporary = CALIBRATION_FILE.with_suffix(".tmp")
    with temporary.open("w", encoding="utf-8") as output:
        parser.write(output)
    os.replace(temporary, CALIBRATION_FILE)


def calculate_accelerometer_calibration(
    pose_means: dict[str, tuple[float, float, float]],
) -> tuple[tuple[float, ...], list[list[float]]]:
    left = pose_means["left"]
    right = pose_means["right"]
    face_up = pose_means["face_up"]
    top = pose_means["top"]
    bottom = pose_means["bottom"]

    # Model the uncalibrated DSU vector as measured = offset + basis * ideal.
    # Opposing edge pairs determine the X/Z basis vectors and two independent
    # offset estimates. The safe controls-up pose then determines Y, avoiding
    # a face-down step while still correcting sensor mounting angle and
    # cross-axis sensitivity.
    x_midpoint = tuple((a + b) * 0.5 for a, b in zip(left, right, strict=True))
    z_midpoint = tuple((a + b) * 0.5 for a, b in zip(top, bottom, strict=True))
    if math.dist(x_midpoint, z_midpoint) > 0.35:
        raise ValueError("edge poses disagree; repeat calibration")

    offset = tuple(
        (a + b) * 0.5 for a, b in zip(x_midpoint, z_midpoint, strict=True)
    )
    basis_x = tuple((a - b) * 0.5 for a, b in zip(left, right, strict=True))
    basis_y = tuple(a - b for a, b in zip(offset, face_up, strict=True))
    basis_z = tuple((a - b) * 0.5 for a, b in zip(top, bottom, strict=True))
    spans = tuple(
        math.sqrt(sum(component * component for component in basis))
        for basis in (basis_x, basis_y, basis_z)
    )
    if any(not 0.70 <= span <= 1.30 for span in spans):
        raise ValueError("pose data is degenerate; repeat calibration")

    # The basis vectors are columns. Inverting this matrix maps every measured
    # sample back into the shared Odin 2 / Thor DSU frame.
    matrix = (
        (basis_x[0], basis_y[0], basis_z[0]),
        (basis_x[1], basis_y[1], basis_z[1]),
        (basis_x[2], basis_y[2], basis_z[2]),
    )
    determinant = (
        matrix[0][0] * (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1])
        - matrix[0][1]
        * (matrix[1][0] * matrix[2][2] - matrix[1][2] * matrix[2][0])
        + matrix[0][2]
        * (matrix[1][0] * matrix[2][1] - matrix[1][1] * matrix[2][0])
    )
    if abs(determinant) < 0.35:
        raise ValueError("pose axes are not independent; repeat calibration")

    correction = [
        [
            (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1])
            / determinant,
            (matrix[0][2] * matrix[2][1] - matrix[0][1] * matrix[2][2])
            / determinant,
            (matrix[0][1] * matrix[1][2] - matrix[0][2] * matrix[1][1])
            / determinant,
        ],
        [
            (matrix[1][2] * matrix[2][0] - matrix[1][0] * matrix[2][2])
            / determinant,
            (matrix[0][0] * matrix[2][2] - matrix[0][2] * matrix[2][0])
            / determinant,
            (matrix[0][2] * matrix[1][0] - matrix[0][0] * matrix[1][2])
            / determinant,
        ],
        [
            (matrix[1][0] * matrix[2][1] - matrix[1][1] * matrix[2][0])
            / determinant,
            (matrix[0][1] * matrix[2][0] - matrix[0][0] * matrix[2][1])
            / determinant,
            (matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0])
            / determinant,
        ],
    ]
    return offset, correction


class MotionCalibrator:
    def __init__(self) -> None:
        pyxel.init(
            320,
            240,
            title="AYN Odin 2 / Thor Sensor Calibration",
            fps=30,
            quit_key=pyxel.KEY_ESCAPE,
            display_scale=4,
        )
        self.state = "intro"
        self.status = "Press A to begin or B to quit"
        self.process: subprocess.Popen[bytes] | None = None
        self.process_output = ""
        self.progress = 0
        self.dsu: DsuClient | None = None
        self.latest_accel: tuple[float, float, float] | None = None
        self.latest_gyro: tuple[float, float, float] | None = None
        self.pose_index = 0
        self.pose_samples: list[tuple[float, float, float]] = []
        self.pose_means: dict[str, tuple[float, float, float]] = {}
        self.collecting = False
        self.old_accelerometer: dict[str, str] | None = None
        self.committed = False
        self.bridge_stopped = False
        atexit.register(self.ensure_bridge)
        pyxel.run(self.update, self.draw)

    @staticmethod
    def confirm_pressed() -> bool:
        # AYN's SDL mapping presents its physical A label as Pyxel's B.
        return pyxel.btnp(pyxel.GAMEPAD1_BUTTON_B) or pyxel.btnp(pyxel.KEY_RETURN)

    @staticmethod
    def back_pressed() -> bool:
        # AYN's SDL mapping presents its physical B label as Pyxel's A.
        return pyxel.btnp(pyxel.GAMEPAD1_BUTTON_A) or pyxel.btnp(pyxel.KEY_BACKSPACE)

    def ensure_bridge(self) -> None:
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        restored = False
        if not self.committed:
            restored = self.restore_old_accelerometer()
        if self.dsu is not None:
            self.dsu.close()
            self.dsu = None
        if self.bridge_stopped:
            run_service("start")
            self.bridge_stopped = False
        elif restored:
            run_service("restart")

    def quit(self) -> None:
        self.ensure_bridge()
        pyxel.quit()

    def start_gyro_calibration(self) -> None:
        self.state = "gyro"
        self.status = f"Do not touch the {DEVICE_NAME}"
        self.progress = 0
        run_service("stop")
        self.bridge_stopped = True
        try:
            self.process = subprocess.Popen(
                [
                    str(BRIDGE),
                    "--calibrate",
                    "--calibration-file",
                    str(CALIBRATION_FILE),
                    "--profile",
                    PROFILE,
                    "--calibration-samples",
                    str(CALIBRATION_SAMPLES),
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
            if self.process.stdout is not None:
                os.set_blocking(self.process.stdout.fileno(), False)
        except OSError as error:
            self.state = "error"
            self.status = f"Unable to start calibration: {error}"
            run_service("start")
            self.bridge_stopped = False

    def update_gyro_calibration(self) -> None:
        if self.process is None:
            return
        if self.process.stdout is not None:
            try:
                chunk = os.read(self.process.stdout.fileno(), 4096)
            except BlockingIOError:
                chunk = b""
            if chunk:
                self.process_output += chunk.decode("utf-8", errors="replace")
                matches = re.findall(
                    rf"(\d+)/{CALIBRATION_SAMPLES} stationary",
                    self.process_output,
                )
                if matches:
                    self.progress = min(int(matches[-1]), CALIBRATION_SAMPLES)

        result = self.process.poll()
        if result is None:
            return
        self.process = None
        if result != 0:
            self.state = "error"
            self.status = "Calibration failed: movement detected or sensor timeout"
            run_service("start")
            self.bridge_stopped = False
            return

        self.remove_existing_accelerometer()
        run_service("start")
        self.bridge_stopped = False
        self.dsu = DsuClient()
        self.state = "connecting"
        self.status = "Starting calibrated sensor bridge..."

    def remove_existing_accelerometer(self) -> None:
        parser = read_config()
        if parser.has_section("accelerometer"):
            self.old_accelerometer = dict(parser.items("accelerometer"))
            parser.remove_section("accelerometer")
            write_config(parser)

    def restore_old_accelerometer(self) -> bool:
        if self.old_accelerometer is None:
            return False
        parser = read_config()
        if parser.has_section("accelerometer"):
            parser.remove_section("accelerometer")
        parser.add_section("accelerometer")
        for key, value in self.old_accelerometer.items():
            parser.set("accelerometer", key, value)
        write_config(parser)
        self.old_accelerometer = None
        return True

    def update_dsu(self) -> list[tuple[float, float, float]]:
        if self.dsu is None:
            return []
        accel_samples = []
        for accel, gyro in self.dsu.update():
            self.latest_accel = accel
            self.latest_gyro = gyro
            accel_samples.append(accel)
        if self.state == "connecting" and self.latest_accel is not None:
            self.state = "pose"
            self.status = "Still flat: measuring accelerometer automatically..."
        return accel_samples

    @staticmethod
    def pose_alignment(sample: tuple[float, float, float], target: tuple[float, float, float]) -> float:
        magnitude = math.sqrt(sum(value * value for value in sample))
        if magnitude < 0.01:
            return -1.0
        return sum(a * b for a, b in zip(sample, target, strict=True)) / magnitude

    def begin_pose(self) -> None:
        if self.latest_accel is None:
            self.status = "Waiting for sensor data"
            return
        target = POSES[self.pose_index][2]
        magnitude = math.sqrt(sum(value * value for value in self.latest_accel))
        if not 0.75 <= magnitude <= 1.25 or self.pose_alignment(self.latest_accel, target) < 0.94:
            pose = POSES[self.pose_index][1]
            x, y, z = self.latest_accel
            self.status = f"Need {pose}; sensor is {x:+.2f} {y:+.2f} {z:+.2f} G"
            return
        self.collecting = True
        self.pose_samples.clear()
        if self.pose_index == 0:
            self.status = "Still flat: measuring accelerometer automatically..."
        else:
            self.status = "Hold still..."

    def update_pose_collection(self, samples: list[tuple[float, float, float]]) -> None:
        if not self.collecting:
            return
        target = POSES[self.pose_index][2]
        for sample in samples:
            magnitude = math.sqrt(sum(value * value for value in sample))
            moved = self.pose_samples and math.dist(sample, self.pose_samples[-1]) > 0.08
            if not 0.75 <= magnitude <= 1.25 or self.pose_alignment(sample, target) < 0.94 or moved:
                self.pose_samples.clear()
                x, y, z = sample
                self.status = f"Pose moved/lost: sensor is {x:+.2f} {y:+.2f} {z:+.2f} G"
                continue
            self.pose_samples.append(sample)
            if len(self.pose_samples) < POSE_SAMPLES:
                continue

            mean = tuple(
                sum(sample[axis] for sample in self.pose_samples) / len(self.pose_samples)
                for axis in range(3)
            )
            self.pose_means[POSES[self.pose_index][0]] = mean
            self.collecting = False
            self.pose_samples.clear()
            self.pose_index += 1
            if self.pose_index == len(POSES):
                self.finish_accelerometer_calibration()
            else:
                self.status = "Captured. " + POSE_PROMPTS[POSES[self.pose_index][0]]
            return

    def finish_accelerometer_calibration(self) -> None:
        try:
            offset, correction = calculate_accelerometer_calibration(self.pose_means)
        except ValueError as error:
            self.state = "error"
            self.status = str(error)
            return

        run_service("stop")
        self.bridge_stopped = True
        parser = read_config()
        if parser.has_section("accelerometer"):
            parser.remove_section("accelerometer")
        parser.add_section("accelerometer")
        parser.set("accelerometer", "frame", ACCEL_CALIBRATION_FRAME)
        for axis, name in enumerate(("x", "y", "z")):
            parser.set("accelerometer", f"offset_{name}", f"{offset[axis]:.9g}")
        for row in range(3):
            for column in range(3):
                parser.set(
                    "accelerometer",
                    f"matrix_{row}{column}",
                    f"{correction[row][column]:.9g}",
                )
        write_config(parser)
        self.old_accelerometer = None
        self.committed = True
        run_service("start")
        self.bridge_stopped = False
        if self.dsu is not None:
            self.dsu.close()
        self.dsu = DsuClient()
        self.latest_accel = None
        self.latest_gyro = None
        self.state = "validation"
        self.status = "Calibration saved. Try smooth 45 and 90 degree tilts"

    def cancel(self) -> None:
        self.quit()

    def update(self) -> None:
        if self.state == "intro":
            if self.confirm_pressed():
                self.start_gyro_calibration()
            elif self.back_pressed():
                self.quit()
            return

        if self.state == "gyro":
            self.update_gyro_calibration()
            if self.back_pressed():
                self.cancel()
            return

        samples = self.update_dsu()
        if self.state == "pose":
            self.update_pose_collection(samples)
            if self.state == "pose" and not self.collecting:
                self.begin_pose()
        if self.state in {"pose", "connecting", "error"} and self.back_pressed():
            self.cancel()
        if self.state == "validation" and (
            pyxel.btnp(pyxel.GAMEPAD1_BUTTON_B)
            or pyxel.btnp(pyxel.GAMEPAD1_BUTTON_A)
            or pyxel.btnp(pyxel.KEY_RETURN)
        ):
            self.quit()

    @staticmethod
    def draw_arrow(x: int, y: int, dx: int, dy: int, color: int = 10) -> None:
        pyxel.line(x, y, x + dx, y + dy, color)
        if abs(dx) > abs(dy):
            tip_x = x + dx
            pyxel.tri(tip_x, y, tip_x - (5 if dx > 0 else -5), y - 3,
                      tip_x - (5 if dx > 0 else -5), y + 3, color)
        else:
            tip_y = y + dy
            pyxel.tri(x, tip_y, x - 3, tip_y - (5 if dy > 0 else -5),
                      x + 3, tip_y - (5 if dy > 0 else -5), color)

    def draw_device(self, pose: str) -> None:
        color = 6
        screen = 1
        if pose in {"face_up", "face_down"}:
            x, y, width, height = 105, 82, 110, 68
            pyxel.rect(x, y, width, height, color)
            pyxel.rectb(x, y, width, height, 7)
            if pose == "face_up":
                pyxel.rect(x + 25, y + 8, 60, 52, screen)
                pyxel.circb(x + 13, y + 23, 6, 7)
                pyxel.circb(x + 97, y + 44, 6, 7)
                if IS_THOR:
                    pyxel.line(x + 20, y, x + 20, y - 18, 5)
                    pyxel.line(x + 90, y, x + 90, y - 18, 5)
                    pyxel.rectb(x + 20, y - 38, 70, 20, 5)
                    pyxel.text(141, 111, "BASE UP", 7)
                else:
                    pyxel.text(135, 111, "CONTROLS UP", 7)
            else:
                pyxel.rectb(x + 28, y + 12, 54, 44, 5)
                pyxel.text(147, 111, "BACK", 7)
                pyxel.rect(x + 6, y + height, 12, 14, 5)
                pyxel.rect(x + width - 18, y + height, 12, 14, 5)
                pyxel.text(104, 159, "HOLD LEVEL / EQUAL SUPPORTS", 5)
            self.draw_arrow(160, 63, 0, 14)
        elif pose in {"left", "right"}:
            x, y, width, height = 133, 68, 54, 104
            pyxel.rect(x, y, width, height, color)
            pyxel.rectb(x, y, width, height, 7)
            pyxel.rect(x + 6, y + 23, 42, 58, screen)
            edge_x = x if pose == "left" else x + width - 1
            pyxel.line(edge_x, y, edge_x, y + height, 10)
            self.draw_arrow(edge_x + (-15 if pose == "left" else 15), 105,
                            12 if pose == "left" else -12, 0)
        else:
            x, y, width, height = 99, 94, 122, 44
            pyxel.rect(x, y, width, height, color)
            pyxel.rectb(x, y, width, height, 7)
            pyxel.rect(x + 30, y + 6, 62, 32, screen)
            edge_y = y if pose == "top" else y + height - 1
            pyxel.line(x, edge_y, x + width, edge_y, 10)
            self.draw_arrow(160, edge_y + (-16 if pose == "top" else 16),
                            0, 13 if pose == "top" else -13)

        pyxel.line(75, 180, 245, 180, 5)
        pyxel.text(148, 184, "FLAT SURFACE", 5)

    @staticmethod
    def draw_progress(value: int, maximum: int, y: int = 204) -> None:
        pyxel.rect(40, y, 240, 10, 1)
        pyxel.rectb(40, y, 240, 10, 7)
        if maximum:
            pyxel.rect(42, y + 2, int(236 * value / maximum), 6, 11)

    def draw_validation(self) -> None:
        pyxel.circb(160, 126, 56, 7)
        pyxel.line(104, 126, 216, 126, 5)
        pyxel.line(160, 70, 160, 182, 5)
        if self.latest_accel is not None:
            x = max(-1.0, min(1.0, self.latest_accel[0]))
            z = max(-1.0, min(1.0, self.latest_accel[2]))
            pyxel.circ(160 + int(x * 50), 126 - int(z * 50), 4, 10)
            pyxel.text(78, 193,
                       f"accel {self.latest_accel[0]:+.3f} {self.latest_accel[1]:+.3f} {self.latest_accel[2]:+.3f} G",
                       7)
        if self.latest_gyro is not None:
            pyxel.text(78, 202,
                       f"gyro  {self.latest_gyro[0]:+.2f} {self.latest_gyro[1]:+.2f} {self.latest_gyro[2]:+.2f} d/s",
                       7)

    def draw(self) -> None:
        pyxel.cls(0)
        pyxel.rect(8, 8, 304, 224, 1)
        pyxel.rectb(8, 8, 304, 224, 7)
        pyxel.text(88, 17, "ODIN 2 / THOR SENSOR CALIBRATION", 10)

        if self.state == "intro":
            intro = (
                "Open the lid and place the BASE flat, controls up."
                if IS_THOR
                else "Place the DEVICE flat on its back, controls up."
            )
            pyxel.text(57, 38, intro, 7)
            pyxel.text(43, 48, "One flat pass, then edge poses capture automatically.", 6)
            self.draw_device("face_up")
        elif self.state == "gyro":
            pyxel.text(75, 38, "Step 1/6: FLAT - stationary gyro zero", 7)
            self.draw_device("face_up")
            self.draw_progress(self.progress, CALIBRATION_SAMPLES)
        elif self.state == "pose":
            pose, title, _target = POSES[self.pose_index]
            pyxel.text(78, 38, f"Step {self.pose_index + 2}/6: {title}", 7)
            self.draw_device(pose)
            if self.collecting:
                self.draw_progress(len(self.pose_samples), POSE_SAMPLES)
        elif self.state == "connecting":
            pyxel.text(110, 100, "Starting sensor bridge...", 7)
        elif self.state == "validation":
            pyxel.text(74, 38, "Validation: try smooth 45 and 90 degree tilts", 7)
            self.draw_validation()
        elif self.state == "error":
            pyxel.text(135, 96, "CALIBRATION ERROR", 8)

        pyxel.text(20, 220, self.status[:70], 7)
        if self.state in {"intro", "validation"}:
            pyxel.text(248, 220, "A: OK  B: BACK", 6)
        elif self.state == "pose":
            pyxel.text(220, 220, "AUTO CAPTURE  B: CANCEL", 6)


if __name__ == "__main__":
    MotionCalibrator()
