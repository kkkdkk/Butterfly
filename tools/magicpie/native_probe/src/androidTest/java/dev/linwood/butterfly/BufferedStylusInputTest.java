package dev.linwood.butterfly;

import android.app.Activity;
import android.app.Instrumentation;
import android.os.Bundle;
import android.view.InputDevice;
import android.view.MotionEvent;

import java.io.PrintWriter;
import java.io.StringWriter;
import java.util.ArrayList;
import java.util.List;

/** Dependency-free on-device regression runner for {@link BufferedStylusInput}. */
public final class BufferedStylusInputTest extends Instrumentation {
    private static final long DOWN_TIME = 1_000;
    private static final int SOURCE = InputDevice.SOURCE_TOUCHSCREEN | InputDevice.SOURCE_STYLUS;

    @Override
    public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        start();
    }

    @Override
    public void onStart() {
        Bundle result = new Bundle();
        try {
            verifyMoveHistoryIsReplayed();
            verifyUpHistoryIsReplayedBeforeUp();
            verifyCancelHistoryIsNotReplayed();
            result.putString("stream", "BufferedStylusInput: 3 tests passed");
            finish(Activity.RESULT_OK, result);
        } catch (Throwable error) {
            StringWriter trace = new StringWriter();
            error.printStackTrace(new PrintWriter(trace));
            result.putString("shortMsg", error.toString());
            result.putString("stream", trace.toString());
            finish(Activity.RESULT_CANCELED, result);
        }
    }

    private static void verifyMoveHistoryIsReplayed() {
        MotionEvent original = eventWithHistory(MotionEvent.ACTION_MOVE);
        try {
            Capture capture = dispatchAndCapture(original);
            require(capture.originalCount == 1, "MOVE original must be forwarded once");
            require(capture.events.size() == 3, "MOVE must produce two history events plus current");
            assertHistoricalSample(original, 0, capture.events.get(0));
            assertHistoricalSample(original, 1, capture.events.get(1));
            assertCurrent(original, capture.events.get(2), MotionEvent.ACTION_MOVE);
        } finally {
            original.recycle();
        }
    }

    private static void verifyUpHistoryIsReplayedBeforeUp() {
        MotionEvent original = eventWithHistory(MotionEvent.ACTION_UP);
        try {
            Capture capture = dispatchAndCapture(original);
            require(capture.originalCount == 1, "UP original must be forwarded once");
            require(capture.events.size() == 3, "UP must produce two history events plus current");
            assertHistoricalSample(original, 0, capture.events.get(0));
            assertHistoricalSample(original, 1, capture.events.get(1));
            assertCurrent(original, capture.events.get(2), MotionEvent.ACTION_UP);
        } finally {
            original.recycle();
        }
    }

    private static void verifyCancelHistoryIsNotReplayed() {
        MotionEvent original = eventWithHistory(MotionEvent.ACTION_CANCEL);
        try {
            Capture capture = dispatchAndCapture(original);
            require(capture.originalCount == 1, "CANCEL original must be forwarded once");
            require(capture.events.size() == 1, "CANCEL history must not be replayed");
            assertCurrent(original, capture.events.get(0), MotionEvent.ACTION_CANCEL);
        } finally {
            original.recycle();
        }
    }

    private static Capture dispatchAndCapture(MotionEvent original) {
        Capture capture = new Capture();
        BufferedStylusInput.dispatch(original, event -> {
            if (event == original) capture.originalCount++;
            capture.events.add(Snapshot.from(event));
        });
        return capture;
    }

    private static MotionEvent eventWithHistory(int finalAction) {
        MotionEvent.PointerProperties[] properties = properties();
        MotionEvent event = MotionEvent.obtain(
                DOWN_TIME, 1_010, MotionEvent.ACTION_MOVE, properties.length,
                properties, coordinates(1), 0x41, MotionEvent.BUTTON_STYLUS_PRIMARY,
                0.25f, 0.5f, 23, MotionEvent.EDGE_LEFT, SOURCE,
                MotionEvent.FLAG_WINDOW_IS_OBSCURED);
        event.addBatch(1_020, coordinates(2), 0x42);
        event.addBatch(1_030, coordinates(3), 0x43);
        event.setAction(finalAction);
        return event;
    }

    private static MotionEvent.PointerProperties[] properties() {
        MotionEvent.PointerProperties stylus = new MotionEvent.PointerProperties();
        stylus.id = 7;
        stylus.toolType = MotionEvent.TOOL_TYPE_STYLUS;
        MotionEvent.PointerProperties eraser = new MotionEvent.PointerProperties();
        eraser.id = 11;
        eraser.toolType = MotionEvent.TOOL_TYPE_ERASER;
        return new MotionEvent.PointerProperties[]{stylus, eraser};
    }

    private static MotionEvent.PointerCoords[] coordinates(int sample) {
        MotionEvent.PointerCoords[] coordinates = new MotionEvent.PointerCoords[2];
        for (int pointer = 0; pointer < coordinates.length; pointer++) {
            float base = sample * 100 + pointer * 10;
            MotionEvent.PointerCoords value = new MotionEvent.PointerCoords();
            value.x = base + 1;
            value.y = base + 2;
            value.pressure = 0.1f * sample + 0.01f * pointer;
            value.size = 0.2f * sample + 0.01f * pointer;
            value.touchMajor = base + 3;
            value.touchMinor = base + 4;
            value.toolMajor = base + 5;
            value.toolMinor = base + 6;
            value.orientation = 0.05f * sample + 0.01f * pointer;
            value.setAxisValue(MotionEvent.AXIS_TILT, 0.2f * sample + 0.01f * pointer);
            value.setAxisValue(MotionEvent.AXIS_DISTANCE, base + 7);
            value.setAxisValue(MotionEvent.AXIS_GENERIC_1, base + 8);
            coordinates[pointer] = value;
        }
        return coordinates;
    }

    private static void assertHistoricalSample(
            MotionEvent original, int history, Snapshot actual) {
        require(actual.action == MotionEvent.ACTION_MOVE, "history must be replayed as MOVE");
        require(actual.eventTime == original.getHistoricalEventTime(history),
                "historical eventTime changed");
        assertMetadata(original, actual);
        for (int pointer = 0; pointer < original.getPointerCount(); pointer++) {
            MotionEvent.PointerCoords expected = new MotionEvent.PointerCoords();
            original.getHistoricalPointerCoords(pointer, history, expected);
            assertPointer(original, pointer, expected, actual, pointer);
        }
    }

    private static void assertCurrent(MotionEvent original, Snapshot actual, int action) {
        require(actual.action == action, "current action changed");
        require(actual.eventTime == original.getEventTime(), "current eventTime changed");
        assertMetadata(original, actual);
        for (int pointer = 0; pointer < original.getPointerCount(); pointer++) {
            MotionEvent.PointerCoords expected = new MotionEvent.PointerCoords();
            original.getPointerCoords(pointer, expected);
            assertPointer(original, pointer, expected, actual, pointer);
        }
    }

    private static void assertMetadata(MotionEvent original, Snapshot actual) {
        require(actual.downTime == original.getDownTime(), "downTime changed");
        require(actual.pointerCount == original.getPointerCount(), "pointer count changed");
        require(actual.metaState == original.getMetaState(), "meta state changed");
        require(actual.buttonState == original.getButtonState(), "button state changed");
        require(actual.deviceId == original.getDeviceId(), "device id changed");
        require(actual.edgeFlags == original.getEdgeFlags(), "edge flags changed");
        require(actual.source == original.getSource(), "source changed");
        require(actual.flags == original.getFlags(), "flags changed");
        close(actual.xPrecision, original.getXPrecision(), "x precision changed");
        close(actual.yPrecision, original.getYPrecision(), "y precision changed");
    }

    private static void assertPointer(
            MotionEvent original,
            int originalPointer,
            MotionEvent.PointerCoords expected,
            Snapshot actual,
            int actualPointer) {
        require(actual.ids[actualPointer] == original.getPointerId(originalPointer),
                "pointer id changed");
        require(actual.tools[actualPointer] == original.getToolType(originalPointer),
                "tool type changed");
        MotionEvent.PointerCoords value = actual.coordinates[actualPointer];
        close(value.x, expected.x, "x changed");
        close(value.y, expected.y, "y changed");
        close(value.pressure, expected.pressure, "pressure changed");
        close(value.size, expected.size, "size changed");
        close(value.touchMajor, expected.touchMajor, "touchMajor changed");
        close(value.touchMinor, expected.touchMinor, "touchMinor changed");
        close(value.toolMajor, expected.toolMajor, "toolMajor changed");
        close(value.toolMinor, expected.toolMinor, "toolMinor changed");
        close(value.orientation, expected.orientation, "orientation changed");
        close(value.getAxisValue(MotionEvent.AXIS_TILT),
                expected.getAxisValue(MotionEvent.AXIS_TILT), "tilt changed");
        close(value.getAxisValue(MotionEvent.AXIS_DISTANCE),
                expected.getAxisValue(MotionEvent.AXIS_DISTANCE), "distance changed");
        close(value.getAxisValue(MotionEvent.AXIS_GENERIC_1),
                expected.getAxisValue(MotionEvent.AXIS_GENERIC_1), "generic axis changed");
    }

    private static void close(float actual, float expected, String message) {
        require(Math.abs(actual - expected) < 0.0001f, message);
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static final class Capture {
        final List<Snapshot> events = new ArrayList<>();
        int originalCount;
    }

    private static final class Snapshot {
        final int action;
        final long downTime;
        final long eventTime;
        final int pointerCount;
        final int metaState;
        final int buttonState;
        final int deviceId;
        final int edgeFlags;
        final int source;
        final int flags;
        final float xPrecision;
        final float yPrecision;
        final int[] ids;
        final int[] tools;
        final MotionEvent.PointerCoords[] coordinates;

        private Snapshot(MotionEvent event) {
            action = event.getActionMasked();
            downTime = event.getDownTime();
            eventTime = event.getEventTime();
            pointerCount = event.getPointerCount();
            metaState = event.getMetaState();
            buttonState = event.getButtonState();
            deviceId = event.getDeviceId();
            edgeFlags = event.getEdgeFlags();
            source = event.getSource();
            flags = event.getFlags();
            xPrecision = event.getXPrecision();
            yPrecision = event.getYPrecision();
            ids = new int[pointerCount];
            tools = new int[pointerCount];
            coordinates = new MotionEvent.PointerCoords[pointerCount];
            for (int pointer = 0; pointer < pointerCount; pointer++) {
                ids[pointer] = event.getPointerId(pointer);
                tools[pointer] = event.getToolType(pointer);
                coordinates[pointer] = new MotionEvent.PointerCoords();
                event.getPointerCoords(pointer, coordinates[pointer]);
            }
        }

        static Snapshot from(MotionEvent event) {
            return new Snapshot(event);
        }
    }
}
