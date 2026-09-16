package dev.linwood.butterfly.magicpie;

import android.app.Activity;
import android.content.Context;
import android.os.SystemClock;
import android.util.Log;
import android.view.MotionEvent;

import androidx.annotation.Keep;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/** Copies complete MotionEvents on the UI thread and expands them off-thread. */
@Keep
final class InkDiagnosticRecorder {
    private static final String TAG = "MagicpieInk";
    private static final int MAX_EVENTS = 4096;
    private static final int MAX_SAMPLES = 8192;

    private final Context context;
    private final ThreadPoolExecutor writer = new ThreadPoolExecutor(
            0, 1, 10, TimeUnit.SECONDS, new LinkedBlockingQueue<>(), runnable -> {
                Thread thread = new Thread(runnable, "MagicpieInkDiagnosticWriter");
                thread.setDaemon(true);
                return thread;
            });
    private long nextStrokeId;
    private Stroke activeStroke;

    InkDiagnosticRecorder(Activity activity) {
        context = activity.getApplicationContext();
        writer.allowCoreThreadTimeOut(true);
    }

    boolean hasActiveStroke() {
        return activeStroke != null;
    }

    long beginStroke(String mode, boolean eligibleAtDown, boolean nativeReadyAtDown) {
        long strokeId = ++nextStrokeId;
        activeStroke = new Stroke(strokeId, mode, eligibleAtDown, nativeReadyAtDown);
        return strokeId;
    }

    void record(MotionEvent event) {
        Stroke stroke = activeStroke;
        if (stroke == null) return;
        int samples = (event.getHistorySize() + 1) * event.getPointerCount();
        if (stroke.events.size() >= MAX_EVENTS || stroke.sampleCount + samples > MAX_SAMPLES) {
            stroke.truncated = true;
            stroke.droppedEvents++;
            stroke.droppedSamples += samples;
            return;
        }
        stroke.events.add(MotionEvent.obtain(event));
        stroke.sampleCount += samples;
    }

    void finishStroke(boolean forwarded, String endReason) {
        Stroke stroke = activeStroke;
        if (stroke == null) return;
        activeStroke = null;
        stroke.forwarded = forwarded;
        stroke.endReason = endReason;
        stroke.finishedWallClockMs = System.currentTimeMillis();
        stroke.finishedUptimeMs = SystemClock.uptimeMillis();
        Log.i(TAG, "Diagnostic stroke mode=" + stroke.mode
                + " strokeId=" + stroke.strokeId
                + " events=" + stroke.events.size()
                + " samples=" + stroke.sampleCount
                + " truncated=" + (stroke.truncated ? 1 : 0)
                + " forwarded=" + (stroke.forwarded ? 1 : 0));
        writer.execute(() -> writeStroke(stroke));
    }

    private void writeStroke(Stroke stroke) {
        try {
            File directory = context.getExternalFilesDir("ink-diagnostics");
            if (directory == null || (!directory.isDirectory() && !directory.mkdirs())) {
                Log.w(TAG, "Diagnostic stroke file unavailable strokeId=" + stroke.strokeId);
                return;
            }
            File output = new File(directory, String.format(Locale.US,
                    "stroke-%06d-%d-%s.json", stroke.strokeId,
                    stroke.startedWallClockMs, stroke.mode));
            try (OutputStreamWriter stream = new OutputStreamWriter(
                    new FileOutputStream(output), StandardCharsets.UTF_8)) {
                stream.write(toJson(stroke).toString());
            }
            Log.i(TAG, "Diagnostic stroke written strokeId=" + stroke.strokeId
                    + " path=" + output.getAbsolutePath());
        } catch (Exception error) {
            Log.w(TAG, "Diagnostic stroke write failed strokeId=" + stroke.strokeId, error);
        } finally {
            for (MotionEvent event : stroke.events) event.recycle();
            stroke.events.clear();
        }
    }

    private static JSONObject toJson(Stroke stroke) throws Exception {
        JSONObject json = new JSONObject();
        json.put("schemaVersion", 1);
        json.put("mode", stroke.mode);
        json.put("strokeId", stroke.strokeId);
        json.put("startedWallClockMs", stroke.startedWallClockMs);
        json.put("finishedWallClockMs", stroke.finishedWallClockMs);
        json.put("startedUptimeMs", stroke.startedUptimeMs);
        json.put("finishedUptimeMs", stroke.finishedUptimeMs);
        json.put("eligibleAtDown", stroke.eligibleAtDown);
        json.put("nativeReadyAtDown", stroke.nativeReadyAtDown);
        json.put("forwarded", stroke.forwarded);
        json.put("endReason", stroke.endReason);
        json.put("truncated", stroke.truncated);
        json.put("recordedEventCount", stroke.events.size());
        json.put("recordedPointerSampleCount", stroke.sampleCount);
        json.put("droppedEventCount", stroke.droppedEvents);
        json.put("droppedPointerSampleCount", stroke.droppedSamples);
        JSONArray events = new JSONArray();
        for (MotionEvent event : stroke.events) events.put(eventToJson(event));
        json.put("events", events);
        return json;
    }

    private static JSONObject eventToJson(MotionEvent event) throws Exception {
        JSONObject json = new JSONObject();
        json.put("action", event.getAction());
        json.put("actionMasked", event.getActionMasked());
        json.put("actionIndex", event.getActionIndex());
        json.put("downTimeMs", event.getDownTime());
        json.put("eventTimeMs", event.getEventTime());
        json.put("pointerCount", event.getPointerCount());
        json.put("historySize", event.getHistorySize());
        float rawOffsetX = event.getRawX() - event.getX();
        float rawOffsetY = event.getRawY() - event.getY();
        JSONArray samples = new JSONArray();
        for (int history = 0; history < event.getHistorySize(); history++) {
            long time = event.getHistoricalEventTime(history);
            for (int pointer = 0; pointer < event.getPointerCount(); pointer++) {
                samples.put(sampleToJson(event, pointer, history, time, rawOffsetX, rawOffsetY));
            }
        }
        for (int pointer = 0; pointer < event.getPointerCount(); pointer++) {
            samples.put(sampleToJson(event, pointer, -1, event.getEventTime(),
                    rawOffsetX, rawOffsetY));
        }
        json.put("samples", samples);
        return json;
    }

    private static JSONObject sampleToJson(MotionEvent event, int pointer, int history,
                                           long time, float rawOffsetX, float rawOffsetY)
            throws Exception {
        boolean historical = history >= 0;
        float x = historical ? event.getHistoricalX(pointer, history) : event.getX(pointer);
        float y = historical ? event.getHistoricalY(pointer, history) : event.getY(pointer);
        JSONObject json = new JSONObject();
        json.put("eventTimeMs", time);
        json.put("historical", historical);
        json.put("pointerId", event.getPointerId(pointer));
        json.put("toolType", event.getToolType(pointer));
        json.put("x", x);
        json.put("y", y);
        json.put("rawX", x + rawOffsetX);
        json.put("rawY", y + rawOffsetY);
        json.put("pressure", historical
                ? event.getHistoricalPressure(pointer, history) : event.getPressure(pointer));
        return json;
    }

    private static final class Stroke {
        final long strokeId;
        final String mode;
        final boolean eligibleAtDown;
        final boolean nativeReadyAtDown;
        final long startedWallClockMs = System.currentTimeMillis();
        final long startedUptimeMs = SystemClock.uptimeMillis();
        final List<MotionEvent> events = new ArrayList<>();
        long finishedWallClockMs;
        long finishedUptimeMs;
        int sampleCount;
        int droppedEvents;
        int droppedSamples;
        boolean truncated;
        boolean forwarded;
        String endReason;

        Stroke(long strokeId, String mode, boolean eligibleAtDown, boolean nativeReadyAtDown) {
            this.strokeId = strokeId;
            this.mode = mode;
            this.eligibleAtDown = eligibleAtDown;
            this.nativeReadyAtDown = nativeReadyAtDown;
        }
    }
}
