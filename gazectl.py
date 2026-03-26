import argparse
import sys
import os
import time
from screeninfo import get_monitors
import cv2
import mediapipe as mp
import threading
import json
import math
import pyautogui

def parse_args():
    parser = argparse.ArgumentParser(description="Head tracking display switcher for Linux/Windows")
    parser.add_argument("--calibrate", action="store_true", help="Force recalibration")

    default_cal_path = os.path.join(os.path.expanduser("~"), ".local", "share", "gazectl", "calibration.json")
    parser.add_argument("--calibration-file", type=str, default=default_cal_path, help="Custom calibration path")

    parser.add_argument("--camera", type=int, default=0, help="Camera index")
    parser.add_argument("--verbose", action="store_true", help="Print yaw angle continuously")
    parser.add_argument("-v", "--version", action="store_true", help="Print version")

    args, unknown = parser.parse_known_args()
    if args.version:
        print("gazectl (Python version)")
        sys.exit(0)

    return args

def list_monitors():
    monitors = []
    try:
        # screeninfo might fail if no display is connected or X11 is not available
        for m in get_monitors():
            monitors.append({
                "id": m.x + m.y, # Simple pseudo-id
                "name": m.name if m.name else f"{m.width}x{m.height}",
                "x": m.x,
                "y": m.y,
                "width": m.width,
                "height": m.height
            })
    except Exception as e:
        pass
    return monitors


class FaceTracker:
    def __init__(self, smoothing=0.3):
        self.smoothing = smoothing
        self.lock = threading.Lock()
        self._latestYaw = None
        self._smoothedYaw = None
        self._latestPitch = None
        self._smoothedPitch = None
        self._frameCount = 0

        self.camera_index = 0
        self.cap = None
        self.running = False
        self.thread = None

        # Initialize MediaPipe Face Mesh
        self.mp_face_mesh = mp.solutions.face_mesh
        self.face_mesh = self.mp_face_mesh.FaceMesh(
            max_num_faces=1,
            refine_landmarks=False,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5
        )

    @property
    def latestYaw(self):
        with self.lock:
            return self._smoothedYaw

    @property
    def latestPitch(self):
        with self.lock:
            return self._smoothedPitch

    @property
    def frameCount(self):
        with self.lock:
            return self._frameCount

    def start(self, cameraIndex=0):
        self.camera_index = cameraIndex
        self.cap = cv2.VideoCapture(self.camera_index)
        if not self.cap.isOpened():
            raise Exception(f"Cannot open camera {cameraIndex}")

        self.running = True
        self.thread = threading.Thread(target=self._capture_loop, daemon=True)
        self.thread.start()

    def stop(self):
        self.running = False
        if self.thread:
            self.thread.join()
        if self.cap:
            self.cap.release()
        self.face_mesh.close()

    def _capture_loop(self):
        while self.running:
            success, image = self.cap.read()
            if not success:
                time.sleep(0.01)
                continue

            # To improve performance, optionally mark the image as not writeable to pass by reference.
            image.flags.writeable = False
            image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            results = self.face_mesh.process(image)

            if not results.multi_face_landmarks:
                with self.lock:
                    self._latestYaw = None
                    self._latestPitch = None
                    self._frameCount += 1
                continue

            # Use landmarks to estimate yaw/pitch
            # We use 3D coordinates (x, y, z) of specific landmarks
            # Nose tip (1), left eye corner (33), right eye corner (263)
            # This is a basic estimation. Apple Vision gives Euler angles directly.
            # We will approximate based on facial landmarks or use simpler heuristics.
            face = results.multi_face_landmarks[0]

            nose = face.landmark[1]
            left_eye = face.landmark[33]
            right_eye = face.landmark[263]
            chin = face.landmark[152]

            # Basic Yaw: distance ratio of nose to eyes
            eye_dist = math.sqrt((right_eye.x - left_eye.x)**2 + (right_eye.y - left_eye.y)**2 + (right_eye.z - left_eye.z)**2)
            if eye_dist > 0:
                nose_dist_left = math.sqrt((nose.x - left_eye.x)**2 + (nose.y - left_eye.y)**2 + (nose.z - left_eye.z)**2)
                # Normalizing the yaw roughly to degrees (-90 to 90)
                yaw_ratio = nose_dist_left / eye_dist
                yaw_degrees = (yaw_ratio - 0.5) * 180.0
            else:
                yaw_degrees = 0.0

            # Basic Pitch: relative vertical position of nose between eyes and chin
            face_height = math.sqrt((chin.x - nose.x)**2 + (chin.y - nose.y)**2 + (chin.z - nose.z)**2) * 2 # approximate
            if face_height > 0:
                pitch_ratio = (nose.y - min(left_eye.y, right_eye.y)) / abs(chin.y - min(left_eye.y, right_eye.y))
                pitch_degrees = (pitch_ratio - 0.5) * -180.0
            else:
                pitch_degrees = 0.0

            with self.lock:
                self._latestYaw = yaw_degrees
                if self._smoothedYaw is not None:
                    self._smoothedYaw = self._smoothedYaw + self.smoothing * (yaw_degrees - self._smoothedYaw)
                else:
                    self._smoothedYaw = yaw_degrees

                if self._smoothedPitch is not None:
                    self._smoothedPitch = self._smoothedPitch + self.smoothing * (pitch_degrees - self._smoothedPitch)
                else:
                    self._smoothedPitch = pitch_degrees
                self._latestPitch = pitch_degrees
                self._frameCount += 1


class Calibration:

    @staticmethod
    def load(path):
        if not os.path.exists(path):
            return None
        try:
            with open(path, 'r') as f:
                data = json.load(f)

            # Basic schema validation
            if not isinstance(data, dict):
                raise ValueError("Calibration data is not a dictionary.")
            for k, v in data.items():
                if not isinstance(v, dict) or 'yaw' not in v or 'pitch' not in v:
                    raise ValueError(f"Monitor {k} is missing yaw or pitch.")
            return data
        except Exception as e:
            print(f"Warning: Failed to load calibration file {path}: {e}")
            return None


    @staticmethod
    def save(cal, path):
        dir_path = os.path.dirname(path)
        if dir_path:
            try:
                os.makedirs(dir_path, exist_ok=True)
            except Exception as e:
                print(f"Error creating directory {dir_path}: {e}")
                return
        try:
            with open(path, 'w') as f:
                json.dump(cal, f, indent=4)
        except Exception as e:
            print(f"Error saving calibration to {path}: {e}")

    @staticmethod
    def run(face_tracker, monitors):
        cal = {}
        for m in monitors:
            print(f"Look at monitor '{m['name']}' and press Enter...")
            input()
            print("Sampling for 2 seconds...")
            start = time.time()
            yaws = []
            pitches = []
            while time.time() - start < 2.0:
                yaw = face_tracker.latestYaw
                pitch = face_tracker.latestPitch
                if yaw is not None and pitch is not None:
                    yaws.append(yaw)
                    pitches.append(pitch)
                time.sleep(0.033)

            if not yaws:
                print("Failed to detect face. Try again.")
                return None

            avg_yaw = sum(yaws) / len(yaws)
            avg_pitch = sum(pitches) / len(pitches)
            cal[str(m['id'])] = {"yaw": avg_yaw, "pitch": avg_pitch}
            print(f"Recorded: Yaw={avg_yaw:.2f}, Pitch={avg_pitch:.2f}")
        return cal

    @staticmethod
    def target_monitor(yaw, pitch, calibration, current_monitor):
        # Simplistic version: find the monitor with the closest yaw/pitch distance
        best_id = current_monitor
        min_dist = float('inf')
        for m_id, point in calibration.items():
            dist = math.sqrt((yaw - point['yaw'])**2 + (pitch - point['pitch'])**2)
            if dist < min_dist:
                min_dist = dist
                best_id = m_id
        return int(best_id)

def main():
    args = parse_args()
    monitors = list_monitors()
    if len(monitors) < 2:
        print(f"Need at least 2 monitors (found {len(monitors)})")
        # For testing, we might want to proceed even with 1 monitor if mocked, but let's stick to the Swift logic.
        if not os.environ.get('TEST_ENV'):
            sys.exit(1)

    tracker = FaceTracker()
    try:
        tracker.start(cameraIndex=args.camera)
    except Exception as e:
        print(f"Cannot open camera {args.camera}: {e}")
        sys.exit(1)

    time.sleep(1.0) # Wait for camera
    initial_frames = tracker.frameCount
    time.sleep(1.0)
    if tracker.frameCount == initial_frames:
        print("No frames received from camera")
        tracker.stop()
        sys.exit(1)

    calibration = None
    if not args.calibrate:
        calibration = Calibration.load(args.calibration_file)
        if calibration:
            print("Loaded calibration")

    if not calibration:
        calibration = Calibration.run(tracker, monitors)
        if not calibration:
            tracker.stop()
            sys.exit(0)
        Calibration.save(calibration, args.calibration_file)

    print("Tracking started. Press Ctrl+C to stop.")

    # Tracking Loop
    switch_cooldown = 0.5
    last_switch_time = 0
    gaze_monitor = monitors[0]['id'] if monitors else 0
    last_applied = gaze_monitor

    # Ensure pyautogui safety checks don't kill the app if cursor hits corner
    pyautogui.FAILSAFE = False

    try:
        while True:
            yaw = tracker.latestYaw
            if yaw is not None:
                pitch = tracker.latestPitch or 0.0
                target_id = Calibration.target_monitor(yaw, pitch, calibration, gaze_monitor)
                gaze_monitor = target_id

                if args.verbose:
                    print(f"Yaw: {yaw:.2f}, Pitch: {pitch:.2f}, Target: {target_id}", end="\r")

                if gaze_monitor != last_applied:
                    now = time.time()
                    if now - last_switch_time >= switch_cooldown:
                        target_m = next((m for m in monitors if m['id'] == target_id), None)
                        if target_m:
                            # Move cursor to the center of the target monitor
                            cx = target_m['x'] + target_m['width'] // 2
                            cy = target_m['y'] + target_m['height'] // 2
                            try:
                                pyautogui.moveTo(cx, cy)
                                pyautogui.click()
                            except Exception as e:
                                pass # Handle X11 display errors gracefully
                            print(f"\nSwitched to {target_m['name']}")

                        last_applied = target_id
                        last_switch_time = now

            time.sleep(0.033)
    except KeyboardInterrupt:
        pass
    finally:
        tracker.stop()
        print("\nExiting.")

if __name__ == "__main__":
    main()
