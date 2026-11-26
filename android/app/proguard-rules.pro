# Classes looked up by name at runtime (package:jni bindings from Dart, and JNI
# from native libraries). R8 must not rename or remove them.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }
-keep class kotlin.Unit { *; }
-keep class androidx.datastore.** { *; }

# MediaPipe Tasks (JNI + protobuf reflection) and its logging/telemetry deps.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-keep class com.google.common.flogger.** { *; }
-keep class com.google.android.datatransport.** { *; }
-dontwarn com.google.mediapipe.**
-dontwarn com.google.protobuf.**
-dontwarn javax.lang.model.**
-dontwarn com.google.auto.value.**

# Aerograph's own hand tracking bridge.
-keep class com.ashutoshranjan.aero_hand_tracker.** { *; }
