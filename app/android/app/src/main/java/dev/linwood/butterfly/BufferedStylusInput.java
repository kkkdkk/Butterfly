package dev.linwood.butterfly;

import android.view.MotionEvent;

import java.util.function.Consumer;

/** Replays Android-batched stylus samples before forwarding the original event. */
public final class BufferedStylusInput {
    private BufferedStylusInput() {
    }

    public static void dispatch(MotionEvent event, Consumer<MotionEvent> consumer) {
        int action = event.getActionMasked();
        if (action == MotionEvent.ACTION_MOVE || action == MotionEvent.ACTION_UP) {
            int pointerCount = event.getPointerCount();
            MotionEvent.PointerProperties[] properties =
                    new MotionEvent.PointerProperties[pointerCount];
            for (int pointer = 0; pointer < pointerCount; pointer++) {
                properties[pointer] = new MotionEvent.PointerProperties();
                event.getPointerProperties(pointer, properties[pointer]);
            }
            for (int history = 0; history < event.getHistorySize(); history++) {
                MotionEvent.PointerCoords[] coordinates =
                        new MotionEvent.PointerCoords[pointerCount];
                for (int pointer = 0; pointer < pointerCount; pointer++) {
                    coordinates[pointer] = new MotionEvent.PointerCoords();
                    event.getHistoricalPointerCoords(pointer, history, coordinates[pointer]);
                }
                MotionEvent replay = MotionEvent.obtain(
                        event.getDownTime(),
                        event.getHistoricalEventTime(history),
                        MotionEvent.ACTION_MOVE,
                        pointerCount,
                        properties,
                        coordinates,
                        event.getMetaState(),
                        event.getButtonState(),
                        event.getXPrecision(),
                        event.getYPrecision(),
                        event.getDeviceId(),
                        event.getEdgeFlags(),
                        event.getSource(),
                        event.getFlags());
                try {
                    consumer.accept(replay);
                } finally {
                    replay.recycle();
                }
            }
        }
        consumer.accept(event);
    }
}
