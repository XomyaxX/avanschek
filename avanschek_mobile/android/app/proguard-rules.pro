# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# CameraX
-keep class androidx.camera.core.** { *; }
-keepclassmembers class androidx.camera.core.** { *; }
-dontwarn androidx.camera.core.**
-keep class androidx.camera.lifecycle.** { *; }
-keepclassmembers class androidx.camera.lifecycle.** { *; }
-dontwarn androidx.camera.lifecycle.**
-keep class androidx.camera.view.** { *; }
-keepclassmembers class androidx.camera.view.** { *; }
-dontwarn androidx.camera.view.**
-keep class androidx.camera.camera2.** { *; }
-keepclassmembers class androidx.camera.camera2.** { *; }
-dontwarn androidx.camera.camera2.**

# ML Kit / Mobile Scanner
-keep class com.google.mlkit.** { *; }
-keepclassmembers class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keepclassmembers class com.google.android.gms.internal.mlkit_** { *; }
-dontwarn com.google.android.gms.internal.mlkit_**
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keepclassmembers class dev.steenbakker.mobile_scanner.** { *; }
-dontwarn dev.steenbakker.mobile_scanner.**

# Google Play Core (deferred components)
-dontwarn com.google.android.play.core.**

# Keep exception names for proper error reporting
-keepattributes Exceptions,InnerClasses,Signature,Deprecated,SourceFile,LineNumberTable,*Annotation*,EnclosingMethod
