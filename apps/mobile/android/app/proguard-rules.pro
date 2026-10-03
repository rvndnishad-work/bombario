# Release builds are minified with R8. The AdMob SDK (google_mobile_ads)
# pulls in WorkManager, whose Room database classes are created by
# reflection at app start; without these rules R8 strips them and the app
# crashes on launch ("Failed to create an instance of
# androidx.work.impl.WorkDatabase").
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.** { *; }
-keep class androidx.startup.** { *; }
