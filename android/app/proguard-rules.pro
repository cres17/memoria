-keep class com.memoria.** { *; }
-keepattributes *Annotation*

# TFLite
-keep class org.tensorflow.** { *; }
-keep class org.tensorflow.lite.** { *; }
-keepclassmembers class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.**

# AdMob / Google Mobile Ads
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# Flutter
-keep class io.flutter.** { *; }
-keepclassmembers class io.flutter.** { *; }
-dontwarn io.flutter.**

# Kotlin
-keep class kotlin.** { *; }
-dontwarn kotlin.**
