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

## Input batching comparison

Force-stop the probe before each arm, then start the same APK with
`--ez unbufferedInput false` (baseline) or `--ez unbufferedInput true`.
Press **Start native ink**, draw one short line, wait 20 seconds, then draw
a second line. Both arms consume canvas touches; only the second calls
`requestUnbufferedDispatch` before returning, as FlutterView does. No Flutter
engine, document commit, or per-stroke native restart is involved.

Read `MagicpieNativeProbe` logs for the selected arm, native start, DOWN/UP/CANCEL,
arrival lag, and history counts. Correlate cancellations with InputDispatcher
logs. An installed APK or visible native line alone does not verify Android
input delivery. This tests a suspected difference, not an established fix.

## Shared-bitmap pressure experiment

Prefer the smaller `--ez nativePressure true` experiment first: it updates
the fixed brush width synchronously inside the native sample callback, before
the library draws that sample. Width is a diagnostic linear 2–14 pixels for
normalized pressure 0–1. Valid DOWN/MOVE samples update width; UP does not
collapse it to zero. No per-sample UI post, bitmap repaint, or native restart
is involved. This mode takes precedence over `bitmapPressure` if both are set.

Fresh-launch with `--ez bitmapPressure true`, then press **Start native ink**.
This mode deliberately replaces the fixed native brush with an independent
pressure-to-radius rasterizer in the shared bitmap. Android stylus history is
expanded and each delivered batch updates only its dirty rectangle through
`renderRect`. There is no per-stroke stop/setup/start and no Flutter renderer.
The ordinary fixed-brush probe remains unchanged when the extra is absent.

Compare light/heavy drawing while the pen is still down, not just after lift.
This first experiment uses buffered Android input (not native callbacks), so
latency remains an explicit acceptance question. UP logs report region-update
count and maximum renderRect duration. It is not a note editor or production
pressure algorithm; no vendor drawing implementation is copied.
