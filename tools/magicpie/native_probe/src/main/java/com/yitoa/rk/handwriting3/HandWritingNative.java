package com.yitoa.rk.handwriting3;

import android.graphics.Bitmap;
import android.graphics.Rect;

import java.lang.ref.WeakReference;

/**
 * Minimal ABI bridge for the public libhandwriting_jni.so on the Magicpie M1.
 *
 * <p>The package, class, callback names and native descriptors are fixed by the
 * device library's JNI registration table. In particular, the installed
 * library exposes a four-argument brush native whose last parameter is a
 * boolean. No native binary is bundled in this project.</p>
 */
public final class HandWritingNative {
    public interface EventListener {
        void onEvent(HandWritingEvent event);
    }

    static {
        System.loadLibrary("handwriting_jni");
    }

    private final HandWritingEvent reusableEvent = new HandWritingEvent();
    private final int nativePointer;
    private EventListener listener;

    public HandWritingNative() {
        nativePointer = native_init(new WeakReference<>(this));
        if (nativePointer == 0) {
            throw new IllegalStateException("native_init returned a null pointer");
        }
    }

    public void setEventListener(EventListener listener) {
        this.listener = listener;
    }

    public void rotate(int rotation) {
        native_handwriting_rotate(nativePointer, rotation);
    }

    public boolean init(Rect screenRect) {
        return native_handwriting_init(nativePointer, screenRect);
    }

    public boolean setup(Bitmap bitmap) {
        return native_handwriting_setup(nativePointer, bitmap);
    }

    public boolean start() {
        return native_handwriting_start(nativePointer);
    }

    public boolean stop() {
        return native_handwriting_stop(nativePointer);
    }

    public void clear() {
        native_handwriting_clear(nativePointer);
    }

    public void setBrush(int width, int color, boolean enabled) {
        native_handwriting_render_brush_color(nativePointer, width, color, enabled);
    }

    public void renderRect(Rect rect) {
        native_handwriting_render_rect(nativePointer, rect);
    }

    public void destroy() {
        native_handwriting_destroy(nativePointer);
    }

    private static void postEventFromNative(
            Object reference,
            int toolType,
            int buttonState,
            int action,
            float x,
            float y,
            float pressure,
            boolean valid) {
        @SuppressWarnings("unchecked")
        WeakReference<HandWritingNative> weakReference =
                (WeakReference<HandWritingNative>) reference;
        HandWritingNative bridge = weakReference.get();
        if (bridge == null || bridge.listener == null) {
            return;
        }
        HandWritingEvent event = bridge.reusableEvent;
        event.setToolType(toolType);
        event.setButtonState(buttonState);
        event.setAction(action);
        event.setX(x);
        event.setY(y);
        event.setPressure(pressure);
        event.setValid(valid);
        bridge.listener.onEvent(event);
    }

    @SuppressWarnings("unused")
    private static void postJpegDataFromNative(Object reference, byte[] jpegData) {
        // Required by the library's JNI lookup even though this probe does not
        // use the screenshot path.
    }

    private native int native_init(Object weakReference);
    private native void native_debug(int pointer, boolean enabled);
    private native boolean native_handwriting_init(int pointer, Rect screenRect);
    private native boolean native_handwriting_setup(int pointer, Bitmap bitmap);
    private native boolean native_handwriting_start(int pointer);
    private native boolean native_handwriting_stop(int pointer);
    private native void native_handwriting_clear(int pointer);
    private native void native_handwriting_destroy(int pointer);
    private native void native_handwriting_rotate(int pointer, int rotation);
    private native void native_handwriting_render_rect(int pointer, Rect rect);
    private native void native_handwriting_render_rect_color(int pointer, Rect rect, int color);
    private native void native_handwriting_render_brush_color(
            int pointer, int width, int color, boolean eraser);
    private native boolean native_handwriting_screen_shot_start(
            int pointer, int intervalMs, boolean saveJpeg, boolean updateBitmap);
    private native boolean native_handwriting_screen_shot_stop(int pointer);
}
