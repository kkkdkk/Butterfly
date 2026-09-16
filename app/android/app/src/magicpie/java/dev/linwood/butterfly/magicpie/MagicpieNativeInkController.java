package dev.linwood.butterfly.magicpie;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Rect;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.MotionEvent;
import android.view.PixelCopy;
import android.view.SurfaceView;
import android.view.View;
import android.view.ViewGroup;

import androidx.annotation.Keep;

import com.yitoa.rk.handwriting3.HandWritingEvent;
import com.yitoa.rk.handwriting3.HandWritingNative;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import io.flutter.plugin.common.MethodChannel;
import io.flutter.embedding.android.FlutterView;

/** Experimental Magicpie-only native preview controller. Flutter remains the input owner. */
@Keep
public final class MagicpieNativeInkController {
    private static final String TAG = "MagicpieNativeInk";
    private static final String DIAGNOSTIC_EXTRA = "magicpieInkDiagnostic";
    private static final String DIAGNOSTIC_NORMAL = "normal";
    private static final String DIAGNOSTIC_RECORD_ONLY = "record-only";
    private static final String DIAGNOSTIC_COMMIT_ONLY = "commit-only";
    private static final String DIAGNOSTIC_HANDOFF = "handoff";

    private final Activity activity;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final List<Bitmap> retainedSetupBitmaps = new ArrayList<>();
    private final Object pressureLock = new Object();
    private final String configuredDiagnosticMode;
    private final InkDiagnosticRecorder diagnosticRecorder;

    private HandWritingNative nativeInk;
    private Rect eligibleScreenRect;
    private Rect deferredDirtyRect;
    private SurfaceView flutterSurfaceView;
    private MethodChannel.Result pendingResult;
    private boolean pendingDiagnosticPrepareResponse;
    private int generation;
    private boolean initialized;
    private boolean started;
    private boolean penDown;
    private boolean ordinaryStylusDown;
    private boolean diagnosticsEnabled;
    private boolean diagnosticGestureOwned;
    private long activeDiagnosticStrokeId;
    private long lastCompletedDiagnosticStrokeId;
    private volatile Handler watchdogHandler;
    private volatile long lastMainHeartbeat;

    private int androidDownCount;
    private int androidMoveCount;
    private int androidUpCount;
    private int androidHistoryCount;
    private int androidPressureSamples;
    private float androidPressureMin;
    private float androidPressureMax;
    private int nativePressureSamples;
    private float nativePressureMin;
    private float nativePressureMax;

    public MagicpieNativeInkController(Activity activity) {
        this.activity = activity;
        configuredDiagnosticMode = normalizeDiagnosticMode(
                activity.getIntent().getStringExtra(DIAGNOSTIC_EXTRA));
        diagnosticRecorder = new InkDiagnosticRecorder(activity);
    }

    /**
     * Captures the Flutter SurfaceView region and starts the native fixed-width preview.
     * Rect values are logical coordinates relative to FlutterView; dpr converts them to pixels.
     */
    public void prepare(Map<?, ?> arguments, MethodChannel.Result result) {
        boolean diagnosticRequested = Boolean.TRUE.equals(arguments.get("diagnosticEnabled"));
        diagnosticsEnabled = diagnosticRequested
                && !DIAGNOSTIC_NORMAL.equals(configuredDiagnosticMode);
        String mode = effectiveDiagnosticMode();
        Log.i(TAG, "Prepare diagnosticMode=" + mode
                + " requested=" + (diagnosticRequested ? 1 : 0));
        if (diagnosticRequested && DIAGNOSTIC_NORMAL.equals(mode)) {
            Log.w(TAG, "Diagnostic mode missing or invalid; native diagnostic not started");
            dispose();
            finishPrepare(result, false, true);
            return;
        }
        if (!isSupportedDevice() || penDown) {
            finishPrepare(result, false, diagnosticRequested);
            return;
        }
        if (!isActivityReady()) {
            dispose();
            finishPrepare(result, false, diagnosticRequested);
            return;
        }

        CaptureTarget target = parseCaptureTarget(arguments);
        if (target == null) {
            Log.w(TAG, "Native preview not prepared: Flutter surface or bounds unavailable");
            finishPrepare(result, false, diagnosticRequested);
            return;
        }
        if (!shutdownNativeSession()) {
            finishPrepare(result, false, diagnosticRequested);
            return;
        }

        int operation = beginOperation(result, diagnosticRequested);
        eligibleScreenRect = target.screenRect;
        Log.i(TAG, "Preparing screenRect=" + eligibleScreenRect
                + " rotation=" + activity.getWindowManager().getDefaultDisplay().getRotation());
        deferredDirtyRect = null;
        flutterSurfaceView = target.surfaceView;
        captureSurface(target, operation, bitmap -> startWithBackground(operation, bitmap));
    }

    /** Uses a rasterized Flutter canvas snapshot, never a possibly stale SurfaceView buffer. */
    public void present(Map<?, ?> arguments, MethodChannel.Result result) {
        String mode = effectiveDiagnosticMode();
        if (!DIAGNOSTIC_HANDOFF.equals(mode)) {
            Log.i(TAG, "Present rejected diagnosticMode=" + mode
                    + " strokeId=" + lastCompletedDiagnosticStrokeId);
            result.success(false);
            return;
        }
        if (!isActivityReady()) {
            dispose();
            result.success(false);
            return;
        }
        if (!initialized || nativeInk == null || eligibleScreenRect == null
                || flutterSurfaceView == null) {
            result.success(false);
            return;
        }
        Rect dirtyRect = parsePresentRect(arguments);
        if (dirtyRect == null) {
            result.success(false);
            return;
        }
        Object image = arguments.get("image");
        if (!(image instanceof byte[])) {
            Log.w(TAG, "Native handoff requires a rasterized canvas image");
            dispose();
            result.success(false);
            return;
        }
        if (deferredDirtyRect != null) dirtyRect.union(deferredDirtyRect);
        if (penDown) {
            deferredDirtyRect = dirtyRect;
            result.success(true);
            return;
        }
        Bitmap bitmap = null;
        long decodeStarted = SystemClock.uptimeMillis();
        try {
            byte[] encoded = (byte[]) image;
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inMutable = true;
            options.inPreferredConfig = Bitmap.Config.ARGB_8888;
            bitmap = BitmapFactory.decodeByteArray(encoded, 0, encoded.length, options);
            if (bitmap == null || bitmap.getWidth() != eligibleScreenRect.width()
                    || bitmap.getHeight() != eligibleScreenRect.height()) {
                if (bitmap != null) bitmap.recycle();
                Log.w(TAG, "Rasterized canvas image has invalid dimensions");
                dispose();
                result.success(false);
                return;
            }
        } catch (Throwable error) {
            if (bitmap != null) bitmap.recycle();
            Log.w(TAG, "Rasterized canvas image unavailable", error);
            dispose();
            result.success(false);
            return;
        }
        long decodeMs = SystemClock.uptimeMillis() - decodeStarted;
        deferredDirtyRect = null;
        int operation = beginOperation(result, false);
        applyPresentedBackground(operation, bitmap, dirtyRect, decodeMs);
    }

    /** Stops and destroys native state. A later restart requires an explicit prepare call. */
    public boolean dispose() {
        invalidatePendingOperation();
        if (diagnosticRecorder.hasActiveStroke()) {
            lastCompletedDiagnosticStrokeId = activeDiagnosticStrokeId;
            diagnosticRecorder.finishStroke(!diagnosticGestureOwned, "disposed");
            activeDiagnosticStrokeId = 0;
            // Keep diagnosticGestureOwned sticky until this gesture's UP/CANCEL.
            // Otherwise Flutter would receive an orphan terminal event.
        }
        eligibleScreenRect = null;
        deferredDirtyRect = null;
        flutterSurfaceView = null;
        return shutdownNativeSession();
    }

    /** Audits input and returns whether record-only diagnostics own this gesture. */
    public boolean onMotionEvent(MotionEvent event) {
        int action = event.getActionMasked();
        int actionIndex = event.getActionIndex();
        int toolType = event.getToolType(Math.min(actionIndex, event.getPointerCount() - 1));
        boolean stylusLike = toolType == MotionEvent.TOOL_TYPE_STYLUS
                || toolType == MotionEvent.TOOL_TYPE_ERASER;

        if (action == MotionEvent.ACTION_DOWN) {
            if (diagnosticRecorder.hasActiveStroke()) {
                diagnosticRecorder.finishStroke(
                        !diagnosticGestureOwned,
                        "superseded-down");
                diagnosticGestureOwned = false;
            }
            if (stylusLike && diagnosticsEnabled) {
                boolean eligibleStylus = isEligibleOrdinaryStylusDown(event, toolType);
                boolean nativeReady = initialized && started && nativeInk != null
                        && pendingResult == null;
                activeDiagnosticStrokeId = diagnosticRecorder.beginStroke(
                        effectiveDiagnosticMode(), eligibleStylus, nativeReady);
                diagnosticGestureOwned = DIAGNOSTIC_RECORD_ONLY.equals(effectiveDiagnosticMode())
                        && eligibleStylus && nativeReady;
            } else {
                diagnosticGestureOwned = false;
                activeDiagnosticStrokeId = 0;
            }
        }
        if (diagnosticRecorder.hasActiveStroke()) {
            diagnosticRecorder.record(event);
        }
        boolean consumeGesture = diagnosticGestureOwned;

        if (stylusLike) {
            auditStylusEvent(event, action, actionIndex);
        }

        if (action == MotionEvent.ACTION_DOWN) {
            penDown = stylusLike;
            boolean eligibleStylus = isEligibleOrdinaryStylusDown(event, toolType);
            ordinaryStylusDown = eligibleStylus;
            Log.i(TAG, "DOWN state stylus=" + (toolType == MotionEvent.TOOL_TYPE_STYLUS ? 1 : 0)
                    + " eligible=" + (eligibleStylus ? 1 : 0)
                    + " initialized=" + (initialized ? 1 : 0)
                    + " started=" + (started ? 1 : 0)
                    + " capturePending=" + (pendingResult != null ? 1 : 0));
            if (!eligibleStylus) {
                stopForInputExclusion("ineligible down");
            } else if (pendingResult != null) {
                stopForInputExclusion("stylus down during capture");
            }
        } else if (action == MotionEvent.ACTION_POINTER_DOWN
                || event.getPointerCount() > 1) {
            stopForInputExclusion("multiple pointers");
        } else if (action == MotionEvent.ACTION_BUTTON_PRESS
                || (stylusLike && event.getButtonState() != 0)) {
            stopForInputExclusion("stylus button");
        }

        if (stylusLike && action == MotionEvent.ACTION_UP) {
            if (toolType == MotionEvent.TOOL_TYPE_STYLUS && ordinaryStylusDown) {
                Log.i(TAG, "Native preview retained until rasterized Flutter frame");
            }
            penDown = false;
            ordinaryStylusDown = false;
            logStrokeAudit(event);
        } else if (stylusLike && action == MotionEvent.ACTION_CANCEL) {
            penDown = false;
            ordinaryStylusDown = false;
            stopForInputExclusion("stylus cancel");
        }

        if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
            if (diagnosticRecorder.hasActiveStroke()) {
                lastCompletedDiagnosticStrokeId = activeDiagnosticStrokeId;
                diagnosticRecorder.finishStroke(
                        !consumeGesture,
                        action == MotionEvent.ACTION_UP ? "up" : "cancel");
            }
            diagnosticGestureOwned = false;
            activeDiagnosticStrokeId = 0;
        }
        return consumeGesture;
    }

    private boolean isEligibleOrdinaryStylusDown(MotionEvent event, int toolType) {
        return toolType == MotionEvent.TOOL_TYPE_STYLUS
                && event.getPointerCount() == 1
                && event.getButtonState() == 0
                && eligibleScreenRect != null
                && eligibleScreenRect.contains(
                Math.round(event.getRawX()), Math.round(event.getRawY()));
    }

    private boolean isSupportedDevice() {
        return Build.VERSION.SDK_INT == 27
                && (Build.DEVICE.equals("px30_eink_magicpie")
                || Build.MODEL.equalsIgnoreCase("Magicpie M1"));
    }

    private String effectiveDiagnosticMode() {
        return diagnosticsEnabled ? configuredDiagnosticMode : DIAGNOSTIC_NORMAL;
    }

    private static String normalizeDiagnosticMode(String mode) {
        if (DIAGNOSTIC_RECORD_ONLY.equals(mode)
                || DIAGNOSTIC_COMMIT_ONLY.equals(mode)
                || DIAGNOSTIC_HANDOFF.equals(mode)) {
            return mode;
        }
        return DIAGNOSTIC_NORMAL;
    }

    private boolean isActivityReady() {
        return activity.hasWindowFocus() && !activity.isFinishing() && !activity.isDestroyed();
    }

    private CaptureTarget parseCaptureTarget(Map<?, ?> arguments) {
        Double left = number(arguments.get("left"));
        Double top = number(arguments.get("top"));
        Double width = number(arguments.get("width"));
        Double height = number(arguments.get("height"));
        Double dpr = number(arguments.get("dpr"));
        if (!positive(width) || !positive(height) || !positive(dpr)
                || left == null || top == null || !Double.isFinite(left)
                || !Double.isFinite(top)) {
            return null;
        }

        View flutterView = findFlutterView(activity.getWindow().getDecorView());
        SurfaceView surfaceView = findSurfaceView(flutterView);
        if (flutterView == null || surfaceView == null
                || flutterView.getWidth() == 0 || flutterView.getHeight() == 0) {
            return null;
        }

        int localLeft = (int) Math.floor(left * dpr);
        int localTop = (int) Math.floor(top * dpr);
        int localRight = (int) Math.ceil((left + width) * dpr);
        int localBottom = (int) Math.ceil((top + height) * dpr);
        if (localLeft < 0 || localTop < 0 || localRight <= localLeft
                || localBottom <= localTop || localRight > flutterView.getWidth()
                || localBottom > flutterView.getHeight()) {
            return null;
        }

        int[] flutterLocation = new int[2];
        int[] surfaceLocation = new int[2];
        flutterView.getLocationOnScreen(flutterLocation);
        surfaceView.getLocationOnScreen(surfaceLocation);
        Rect screenRect = new Rect(
                flutterLocation[0] + localLeft,
                flutterLocation[1] + localTop,
                flutterLocation[0] + localRight,
                flutterLocation[1] + localBottom);
        Rect surfaceRect = new Rect(
                screenRect.left - surfaceLocation[0],
                screenRect.top - surfaceLocation[1],
                screenRect.right - surfaceLocation[0],
                screenRect.bottom - surfaceLocation[1]);
        if (surfaceRect.left < 0 || surfaceRect.top < 0
                || surfaceRect.right > surfaceView.getWidth()
                || surfaceRect.bottom > surfaceView.getHeight()) {
            return null;
        }
        return new CaptureTarget(surfaceView, screenRect, surfaceRect);
    }

    private Double number(Object value) {
        if (!(value instanceof Number)) {
            return null;
        }
        double converted = ((Number) value).doubleValue();
        return Double.isFinite(converted) ? converted : null;
    }

    private boolean positive(Double value) {
        return value != null && value > 0 && Double.isFinite(value);
    }

    private Rect parsePresentRect(Map<?, ?> arguments) {
        boolean hasLeft = arguments.containsKey("left");
        boolean hasTop = arguments.containsKey("top");
        boolean hasWidth = arguments.containsKey("width");
        boolean hasHeight = arguments.containsKey("height");
        if (!hasLeft && !hasTop && !hasWidth && !hasHeight) {
            return new Rect(0, 0, eligibleScreenRect.width(), eligibleScreenRect.height());
        }
        if (!(hasLeft && hasTop && hasWidth && hasHeight)) {
            return null;
        }

        Double left = number(arguments.get("left"));
        Double top = number(arguments.get("top"));
        Double width = number(arguments.get("width"));
        Double height = number(arguments.get("height"));
        if (left == null || top == null || !positive(width) || !positive(height)) {
            return null;
        }
        double right = left + width;
        double bottom = top + height;
        if (!Double.isFinite(right) || !Double.isFinite(bottom)) {
            return null;
        }

        int viewportWidth = eligibleScreenRect.width();
        int viewportHeight = eligibleScreenRect.height();
        int clippedLeft = Math.max(0, Math.min(viewportWidth, (int) Math.floor(left)));
        int clippedTop = Math.max(0, Math.min(viewportHeight, (int) Math.floor(top)));
        int clippedRight = Math.max(0, Math.min(viewportWidth, (int) Math.ceil(right)));
        int clippedBottom = Math.max(0, Math.min(viewportHeight, (int) Math.ceil(bottom)));
        if (clippedRight <= clippedLeft || clippedBottom <= clippedTop) {
            return null;
        }
        return new Rect(clippedLeft, clippedTop, clippedRight, clippedBottom);
    }

    private View findFlutterView(View view) {
        if (view == null) {
            return null;
        }
        if (view instanceof FlutterView) {
            return view;
        }
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int index = 0; index < group.getChildCount(); index++) {
                View found = findFlutterView(group.getChildAt(index));
                if (found != null) {
                    return found;
                }
            }
        }
        return null;
    }

    private SurfaceView findSurfaceView(View view) {
        if (view instanceof SurfaceView) {
            return (SurfaceView) view;
        }
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int index = 0; index < group.getChildCount(); index++) {
                SurfaceView found = findSurfaceView(group.getChildAt(index));
                if (found != null) {
                    return found;
                }
            }
        }
        return null;
    }

    private void captureSurface(
            CaptureTarget target, int operation, BitmapConsumer consumer) {
        Bitmap createdBitmap = null;
        try {
            createdBitmap = Bitmap.createBitmap(
                    target.surfaceRect.width(), target.surfaceRect.height(), Bitmap.Config.ARGB_8888);
            final Bitmap bitmap = createdBitmap;
            PixelCopy.request(
                    target.surfaceView,
                    target.surfaceRect,
                    bitmap,
                    copyResult -> {
                        if (operation != generation || pendingResult == null) {
                            bitmap.recycle();
                            return;
                        }
                        if (!isActivityReady() || penDown) {
                            bitmap.recycle();
                            shutdownNativeSession();
                            finishOperation(operation, false);
                            return;
                        }
                        if (copyResult != PixelCopy.SUCCESS) {
                            bitmap.recycle();
                            Log.w(TAG, "Flutter SurfaceView PixelCopy failed: " + copyResult);
                            shutdownNativeSession();
                            finishOperation(operation, false);
                            return;
                        }
                        consumer.accept(bitmap);
                    },
                    mainHandler);
        } catch (Throwable error) {
            if (createdBitmap != null && !createdBitmap.isRecycled()) {
                createdBitmap.recycle();
            }
            Log.w(TAG, "Flutter SurfaceView capture unavailable", error);
            shutdownNativeSession();
            finishOperation(operation, false);
        }
    }

    private void startWithBackground(int operation, Bitmap bitmap) {
        if (!isActivityReady() || operation != generation || pendingResult == null) {
            bitmap.recycle();
            shutdownNativeSession();
            finishOperation(operation, false);
            return;
        }
        try {
            startMainThreadWatchdog();
            nativeInk = new HandWritingNative();
            HandWritingNative sessionInk = nativeInk;
            sessionInk.setEventListener(event -> onNativeEvent(sessionInk, event));
            nativeInk.rotate(activity.getWindowManager().getDefaultDisplay().getRotation());
            if (!nativeInk.init(eligibleScreenRect)) {
                retainedSetupBitmaps.add(bitmap);
                shutdownNativeSession();
                finishOperation(operation, false);
                return;
            }
            initialized = true;
            retainedSetupBitmaps.add(bitmap);
            if (!nativeInk.setup(bitmap)) {
                shutdownNativeSession();
                finishOperation(operation, false);
                return;
            }
            releaseReplacedBitmaps(bitmap);
            nativeInk.setBrush(4, 0, true);
            started = nativeInk.start();
            if (!started) {
                shutdownNativeSession();
            }
            Log.i(TAG, started ? "Native pressure preview started (2-14px)" : "Native preview start failed");
            finishOperation(operation, started);
        } catch (Throwable error) {
            if (!retainedSetupBitmaps.contains(bitmap) && !bitmap.isRecycled()) {
                bitmap.recycle();
            }
            Log.w(TAG, "Native preview unavailable; Flutter remains active", error);
            shutdownNativeSession();
            finishOperation(operation, false);
        }
    }

    private void applyPresentedBackground(
            int operation, Bitmap bitmap, Rect dirtyRect, long decodeMs) {
        retainedSetupBitmaps.add(bitmap);
        try {
            if (!isActivityReady() || penDown || operation != generation || pendingResult == null) {
                retainedSetupBitmaps.remove(bitmap);
                bitmap.recycle();
                shutdownNativeSession();
                finishOperation(operation, false);
                return;
            }
            long stopStarted = SystemClock.uptimeMillis();
            if (started) {
                nativeInk.stop();
                started = false;
            }
            long stopMs = SystemClock.uptimeMillis() - stopStarted;
            long setupStarted = SystemClock.uptimeMillis();
            boolean setupReady = nativeInk.setup(bitmap);
            long setupMs = SystemClock.uptimeMillis() - setupStarted;
            if (!setupReady) {
                shutdownNativeSession();
                finishOperation(operation, false);
                return;
            }
            releaseReplacedBitmaps(bitmap);
            nativeInk.setBrush(4, 0, true);
            long startStarted = SystemClock.uptimeMillis();
            started = nativeInk.start();
            long startMs = SystemClock.uptimeMillis() - startStarted;
            if (!started) {
                shutdownNativeSession();
                finishOperation(operation, false);
                return;
            }
            long renderStarted = SystemClock.uptimeMillis();
            nativeInk.renderRect(dirtyRect);
            // renderRect switches off direct brush mode on this firmware.
            // Restore it for the next stroke in the diagnostic handoff path.
            nativeInk.setBrush(4, 0, true);
            long renderMs = SystemClock.uptimeMillis() - renderStarted;
            if (DIAGNOSTIC_HANDOFF.equals(effectiveDiagnosticMode())) {
                Log.i(TAG, "Diagnostic handoff strokeId=" + lastCompletedDiagnosticStrokeId
                        + " decodeMs=" + decodeMs
                        + " stopMs=" + stopMs
                        + " setupMs=" + setupMs
                        + " startMs=" + startMs
                        + " renderRectMs=" + renderMs);
            }
            Log.i(TAG, "Presented rasterized canvas rect left=" + dirtyRect.left
                    + " top=" + dirtyRect.top
                    + " right=" + dirtyRect.right
                    + " bottom=" + dirtyRect.bottom);
            finishOperation(operation, true);
        } catch (Throwable error) {
            Log.w(TAG, "Native preview handoff failed; Flutter remains active", error);
            shutdownNativeSession();
            finishOperation(operation, false);
        }
    }

    private void stopForInputExclusion(String reason) {
        if (nativeInk == null && pendingResult == null) {
            return;
        }
        Log.i(TAG, "Native preview stopped: " + reason);
        invalidatePendingOperation();
        shutdownNativeSession();
    }

    private int beginOperation(MethodChannel.Result result, boolean diagnosticPrepareResponse) {
        invalidatePendingOperation();
        pendingResult = result;
        pendingDiagnosticPrepareResponse = diagnosticPrepareResponse;
        return generation;
    }

    private void invalidatePendingOperation() {
        generation++;
        if (pendingResult != null) {
            MethodChannel.Result result = pendingResult;
            boolean diagnosticPrepareResponse = pendingDiagnosticPrepareResponse;
            pendingResult = null;
            pendingDiagnosticPrepareResponse = false;
            completeResult(result, false, diagnosticPrepareResponse);
        }
    }

    private void finishOperation(int operation, boolean success) {
        if (operation != generation || pendingResult == null) {
            return;
        }
        MethodChannel.Result result = pendingResult;
        boolean diagnosticPrepareResponse = pendingDiagnosticPrepareResponse;
        pendingResult = null;
        pendingDiagnosticPrepareResponse = false;
        completeResult(result, success, diagnosticPrepareResponse);
    }

    private void finishPrepare(
            MethodChannel.Result result, boolean ready, boolean diagnosticPrepareResponse) {
        completeResult(result, ready, diagnosticPrepareResponse);
    }

    private void completeResult(
            MethodChannel.Result result, boolean ready, boolean diagnosticPrepareResponse) {
        if (!diagnosticPrepareResponse) {
            result.success(ready);
            return;
        }
        Map<String, Object> response = new HashMap<>();
        response.put("ready", ready);
        response.put("diagnosticMode", effectiveDiagnosticMode());
        result.success(response);
    }

    private boolean shutdownNativeSession() {
        boolean success = true;
        if (nativeInk != null) {
            try {
                if (started) {
                    nativeInk.stop();
                }
            } catch (Throwable error) {
                success = false;
                Log.w(TAG, "Native preview stop failed during cleanup", error);
            }
            started = false;
            try {
                nativeInk.destroy();
                nativeInk = null;
                initialized = false;
                recycleRetainedBitmaps();
            } catch (Throwable error) {
                success = false;
                Log.w(TAG, "Native preview destroy failed", error);
            }
        } else {
            initialized = false;
            started = false;
            recycleRetainedBitmaps();
        }
        stopMainThreadWatchdog();
        return success;
    }

    // Experimental diagnostics only: capture our own thread stacks during a
    // stall, without root or per-point logging. Never change native state here.
    private void startMainThreadWatchdog() {
        stopMainThreadWatchdog();
        HandlerThread thread = new HandlerThread("MagicpieInkWatchdog");
        thread.start();
        Handler worker = new Handler(thread.getLooper());
        watchdogHandler = worker;
        lastMainHeartbeat = SystemClock.uptimeMillis();
        worker.post(new Runnable() {
            private boolean reported;

            @Override
            public void run() {
                if (watchdogHandler != worker) return;
                long lag = SystemClock.uptimeMillis() - lastMainHeartbeat;
                if (lag >= 2000 && !reported) {
                    reported = true;
                    Log.w(TAG, "Main thread heartbeat stalled ms=" + lag);
                    for (Map.Entry<Thread, StackTraceElement[]> entry
                            : Thread.getAllStackTraces().entrySet()) {
                        String name = entry.getKey().getName();
                        if (entry.getKey() == Looper.getMainLooper().getThread()
                                || name.contains(".ui") || name.contains(".raster")) {
                            Throwable trace = new Throwable("Ink stall thread=" + name);
                            trace.setStackTrace(entry.getValue());
                            Log.w(TAG, "Ink stall stack", trace);
                        }
                    }
                } else if (lag < 2000) {
                    reported = false;
                }
                mainHandler.post(() -> {
                    if (watchdogHandler == worker) {
                        lastMainHeartbeat = SystemClock.uptimeMillis();
                    }
                });
                worker.postDelayed(this, 1000);
            }
        });
    }

    private void stopMainThreadWatchdog() {
        Handler worker = watchdogHandler;
        watchdogHandler = null;
        if (worker != null) worker.getLooper().quitSafely();
    }

    private void releaseReplacedBitmaps(Bitmap active) {
        for (int index = retainedSetupBitmaps.size() - 1; index >= 0; index--) {
            Bitmap bitmap = retainedSetupBitmaps.get(index);
            if (bitmap != active) {
                bitmap.recycle();
                retainedSetupBitmaps.remove(index);
            }
        }
    }

    private void recycleRetainedBitmaps() {
        for (Bitmap bitmap : retainedSetupBitmaps) {
            bitmap.recycle();
        }
        retainedSetupBitmaps.clear();
    }

    private void auditStylusEvent(MotionEvent event, int action, int actionIndex) {
        int pointerIndex = Math.min(actionIndex, event.getPointerCount() - 1);
        if (action == MotionEvent.ACTION_DOWN) {
            synchronized (pressureLock) {
                androidDownCount = 0;
                androidMoveCount = 0;
                androidUpCount = 0;
                androidHistoryCount = 0;
                androidPressureSamples = 0;
                nativePressureSamples = 0;
            }
        }
        synchronized (pressureLock) {
            if (action == MotionEvent.ACTION_DOWN) {
                androidDownCount++;
            } else if (action == MotionEvent.ACTION_MOVE) {
                androidMoveCount++;
            } else if (action == MotionEvent.ACTION_UP) {
                androidUpCount++;
            }
            addAndroidPressure(event.getPressure(pointerIndex));
            int historySize = event.getHistorySize();
            androidHistoryCount += historySize;
            for (int index = 0; index < historySize; index++) {
                addAndroidPressure(event.getHistoricalPressure(pointerIndex, index));
            }
        }
    }

    private void addAndroidPressure(float pressure) {
        if (!Float.isFinite(pressure)) {
            return;
        }
        if (androidPressureSamples == 0) {
            androidPressureMin = pressure;
            androidPressureMax = pressure;
        } else {
            androidPressureMin = Math.min(androidPressureMin, pressure);
            androidPressureMax = Math.max(androidPressureMax, pressure);
        }
        androidPressureSamples++;
    }

    private void onNativeEvent(HandWritingNative sessionInk, HandWritingEvent event) {
        if (!event.isValid() || !Float.isFinite(event.getPressure())) {
            return;
        }
        if (event.getAction() == HandWritingEvent.ACTION_DOWN
                || event.getAction() == HandWritingEvent.ACTION_MOVE) {
            // Verified in the standalone probe: this callback runs on the
            // native input thread before it draws this sample. Do not post.
            int width = Math.round(2 + 12 * Math.max(0, Math.min(1, event.getPressure())));
            sessionInk.setBrush(width, 0, true);
        }
        synchronized (pressureLock) {
            if (event.getAction() == HandWritingEvent.ACTION_DOWN) {
                nativePressureSamples = 0;
            }
            float pressure = event.getPressure();
            if (nativePressureSamples == 0) {
                nativePressureMin = pressure;
                nativePressureMax = pressure;
            } else {
                nativePressureMin = Math.min(nativePressureMin, pressure);
                nativePressureMax = Math.max(nativePressureMax, pressure);
            }
            nativePressureSamples++;
        }
    }

    private void logStrokeAudit(MotionEvent event) {
        long eventLagMs = Math.max(0L, SystemClock.uptimeMillis() - event.getEventTime());
        synchronized (pressureLock) {
            Log.i(TAG, String.format(Locale.US,
                    "UP stats down=%d move=%d up=%d history=%d eventLagMs=%d "
                            + "androidPressureSamples=%d androidPressureMin=%s androidPressureMax=%s "
                            + "nativeValidPressureSamples=%d nativePressureMin=%s nativePressureMax=%s "
                            + "dynamicWidthPreview=1 widthRange=2..14",
                    androidDownCount,
                    androidMoveCount,
                    androidUpCount,
                    androidHistoryCount,
                    eventLagMs,
                    androidPressureSamples,
                    pressureValue(androidPressureSamples, androidPressureMin),
                    pressureValue(androidPressureSamples, androidPressureMax),
                    nativePressureSamples,
                    pressureValue(nativePressureSamples, nativePressureMin),
                    pressureValue(nativePressureSamples, nativePressureMax)));
        }
    }

    private String pressureValue(int samples, float value) {
        return samples == 0 ? "none" : String.format(Locale.US, "%.4f", value);
    }

    private interface BitmapConsumer {
        void accept(Bitmap bitmap);
    }

    private static final class CaptureTarget {
        final SurfaceView surfaceView;
        final Rect screenRect;
        final Rect surfaceRect;

        CaptureTarget(SurfaceView surfaceView, Rect screenRect, Rect surfaceRect) {
            this.surfaceView = surfaceView;
            this.screenRect = screenRect;
            this.surfaceRect = surfaceRect;
        }
    }
}
