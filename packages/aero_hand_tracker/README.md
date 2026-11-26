# aero_hand_tracker

Local Flutter plugin used by Aerograph. Wraps the MediaPipe Hand Landmarker task
(Android: `com.google.mediapipe:tasks-vision`, iOS: `MediaPipeTasksVision` pod) behind a
single `MethodChannel` named `aero_hand_tracker`.

Frames come from the `camera` plugin image stream (NV21 on Android, BGRA8888 on iOS),
are downscaled/rotated natively, and 21 normalized landmarks per hand are returned.
