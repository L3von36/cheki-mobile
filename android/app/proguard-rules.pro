# Mahtem ProGuard / R8 rules.
#
# The Flutter Gradle plugin injects its own required rules automatically;
# these are extra safety nets so R8 never strips anything the runtime needs.
# All plugins used here (mobile_scanner, url_launcher, share_plus, …) ship
# their own consumer rules inside their AARs.

# Flutter embedding — method channels, plugin registry, platform views.
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.common.** { *; }

# Never warn about optional annotations used by AndroidX / Play Services.
-dontwarn org.jetbrains.annotations.**
-dontwarn java.lang.invoke.**

# The Flutter engine references Play Core (used only for Play Store
# "deferred components" / dynamic feature splits, which Mahtem does not
# use). The library is not bundled, and these paths never execute — tell
# R8 to ignore them (found by running a release build with R8 enabled).
-dontwarn com.google.android.play.core.**
