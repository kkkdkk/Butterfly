# Magicpie native handwriting probe

This is a separate diagnostic APK for the Magicpie M1. It does not replace
Butterfly: its package name is `dev.linwood.butterfly.magicpie.probe`.

The probe intentionally contains no native libraries and requests no Android
permissions. At runtime, `System.loadLibrary("handwriting_jni")` resolves the
device-provided public system library. The JNI class name and descriptors match
the registration table observed in that system binary; no vendor business code
or vendor binary is included.

Build from this directory with:

```powershell
.\build.ps1
```

The APK is copied to
`.magicpie-output/native-probe/magicpie-native-probe-debug.apk`.

Runtime use is deliberately explicit: open the probe and press **Start native
ink**. The canvas area is passed to the system library as an absolute screen
rectangle backed by a mutable ARGB bitmap. **Stop** and leaving the activity
stop the native pipeline; activity destruction also destroys it and sends the
matching disable broadcast.
