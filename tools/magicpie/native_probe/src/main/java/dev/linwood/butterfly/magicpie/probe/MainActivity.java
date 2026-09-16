package dev.linwood.butterfly.magicpie.probe;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.os.Bundle;
import android.util.Log;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

import com.yitoa.rk.handwriting3.HandWritingEvent;
import com.yitoa.rk.handwriting3.HandWritingNative;
import dev.linwood.butterfly.BufferedStylusInput;

/** Standalone, user-triggered probe for the Magicpie native ink path. */
public final class MainActivity extends Activity {
    private static final String TAG = "MagicpieNativeProbe";
    private static final String ACTION_DISABLE = "yitoa.intent.action.HANDWRITING_DISABLE";

    private TextView status;
    private InkView inkView;
    private HandWritingNative nativeInk;
    private boolean initialized;
    private boolean started;
    private int nativeEventCount;
    private int androidStylusEventCount;
    private int androidDownCount;
    private int androidMoveCount;
    private int androidUpCount;
    private int androidCancelCount;
    private int androidHistoryCount;
    private boolean unbufferedInput;
    private boolean bitmapPressure;
    private boolean nativePressure;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        unbufferedInput = getIntent().getBooleanExtra("unbufferedInput", false);
        bitmapPressure = getIntent().getBooleanExtra("bitmapPressure", false);
        nativePressure = getIntent().getBooleanExtra("nativePressure", false);
        if (nativePressure) bitmapPressure = false;
        Log.i(TAG, "Native pressure experiment=" + nativePressure);
        if (bitmapPressure) unbufferedInput = false;
        Log.i(TAG, "Bitmap pressure experiment=" + bitmapPressure);
        Log.i(TAG, "Input experiment unbuffered=" + unbufferedInput);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);

        LinearLayout controls = new LinearLayout(this);
        controls.setGravity(Gravity.CENTER_VERTICAL);
        status = new TextView(this);
        status.setText("Public system library only - stopped");
        status.setTextColor(Color.BLACK);
        status.setPadding(16, 8, 16, 8);
        controls.addView(status, new LinearLayout.LayoutParams(0, -2, 1));
        controls.addView(button("Start native ink", ignored -> startNativeInk()));
        controls.addView(button("Stop", ignored -> stopNativeInk()));
        controls.addView(button("Clear", ignored -> clearNativeInk()));

        inkView = new InkView();
        root.addView(controls, new LinearLayout.LayoutParams(-1, -2));
        root.addView(inkView, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(root);
    }

    private Button button(String label, View.OnClickListener listener) {
        Button button = new Button(this);
        button.setText(label);
        button.setTextColor(Color.BLACK);
        button.setOnClickListener(listener);
        return button;
    }

    private void startNativeInk() {
        if (started) {
            showStatus("Already started");
            return;
        }
        if (inkView.getWidth() == 0 || inkView.getHeight() == 0) {
            inkView.post(this::startNativeInk);
            return;
        }

        try {
            if (nativeInk == null) {
                nativeInk = new HandWritingNative();
                nativeInk.setEventListener(this::onNativeEvent);
            }
            if (!initialized) {
                int[] location = new int[2];
                inkView.getLocationOnScreen(location);
                Rect screenRect = new Rect(
                        location[0],
                        location[1],
                        location[0] + inkView.getWidth(),
                        location[1] + inkView.getHeight());
                inkView.createBitmap();
                nativeInk.rotate(getWindowManager().getDefaultDisplay().getRotation());
                boolean initOk = nativeInk.init(screenRect);
                boolean setupOk = initOk && nativeInk.setup(inkView.getBitmap());
                initialized = initOk && setupOk;
                if (!initialized) {
                    cleanupNativeInk();
                    showStatus("Native init/setup failed: init=" + initOk + ", setup=" + setupOk);
                    return;
                }
                // Required by the installed Magicpie system library to enable
                // the active native brush. Confirmed by on-device A/B.
                if (!bitmapPressure) nativeInk.setBrush(4, 0, true);
            }
            started = nativeInk.start();
            if (!started) {
                cleanupNativeInk();
            }
            showStatus(started ? "Native ink started - write below" : "Native start returned false");
        } catch (Throwable error) {
            cleanupNativeInk();
            showStatus(error.getClass().getSimpleName() + ": " + error.getMessage());
        }
    }

    private void onNativeEvent(HandWritingEvent event) {
        nativeEventCount++;
        HandWritingNative ink = nativeInk;
        if (nativePressure && ink != null && event.isValid()
                && (event.getAction() == HandWritingEvent.ACTION_DOWN
                    || event.getAction() == HandWritingEvent.ACTION_MOVE)) {
            float pressure = event.getPressure();
            if (Float.isNaN(pressure) || Float.isInfinite(pressure)) return;
            int width = Math.round(2 + 12 * Math.max(0, Math.min(1, pressure)));
            // The native input thread calls this listener before drawing this
            // sample. Keep this setter synchronous; posting it would lag ink.
            ink.setBrush(width, 0, true);
        }
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent event) {
        int toolType = event.getToolType(0);
        if (toolType == MotionEvent.TOOL_TYPE_STYLUS
                || toolType == MotionEvent.TOOL_TYPE_ERASER) {
            androidStylusEventCount++;
            int action = event.getActionMasked();
            androidHistoryCount += event.getHistorySize();
            if (action == MotionEvent.ACTION_DOWN) androidDownCount++;
            if (action == MotionEvent.ACTION_MOVE) androidMoveCount++;
            if (action == MotionEvent.ACTION_UP) androidUpCount++;
            if (action == MotionEvent.ACTION_CANCEL) androidCancelCount++;
            if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
                Log.i(TAG, "Android stroke totals down=" + androidDownCount
                        + " move=" + androidMoveCount + " up=" + androidUpCount
                        + " cancel=" + androidCancelCount + " history=" + androidHistoryCount
                        + " nativeEvents=" + nativeEventCount + " started=" + started);
                showStatus(started ? "Native ink running" : "Stopped");
            }
            if (action == MotionEvent.ACTION_DOWN || action == MotionEvent.ACTION_UP
                    || action == MotionEvent.ACTION_CANCEL) {
                Log.i(TAG, "Input action=" + action + " unbuffered=" + unbufferedInput
                        + " eventTime=" + event.getEventTime()
                        + " arrivalLagMs=" + Math.max(0,
                                android.os.SystemClock.uptimeMillis() - event.getEventTime()));
            }
        }
        return super.dispatchTouchEvent(event);
    }

    private void stopNativeInk() {
        if (nativeInk == null || !started) {
            cleanupNativeInk();
            showStatus("Stopped");
            return;
        }
        try {
            boolean nativeResult = nativeInk.stop();
            started = false;
            inkView.invalidate();
            cleanupNativeInk();
            showStatus("Stopped; native result=" + nativeResult);
        } catch (Throwable error) {
            cleanupNativeInk();
            showStatus(error.getClass().getSimpleName() + ": " + error.getMessage());
        }
    }

    private void clearNativeInk() {
        if (nativeInk == null || !initialized) {
            inkView.createBitmap();
            inkView.invalidate();
            showStatus("Canvas cleared; native ink has not been initialized");
            return;
        }
        boolean restart = started;
        if (restart) {
            try {
                nativeInk.stop();
                started = false;
            } catch (Throwable error) {
                cleanupNativeInk();
                showStatus(error.getClass().getSimpleName() + ": " + error.getMessage());
                return;
            }
        }
        try {
            nativeInk.clear();
            inkView.createBitmap();
            if (!nativeInk.setup(inkView.getBitmap())) {
                cleanupNativeInk();
                showStatus("Canvas cleared; native setup failed");
                return;
            }
            inkView.invalidate();
            showStatus("Canvas cleared");
            if (restart) {
                startNativeInk();
            }
        } catch (Throwable error) {
            showStatus(error.getClass().getSimpleName() + ": " + error.getMessage());
        }
    }

    private void showStatus(String message) {
        Log.i(TAG, "State: " + message);
        status.setText("Public system library only - " + message
                + "\nnativeEvents=" + nativeEventCount
                + ", androidStylusEvents=" + androidStylusEventCount
                + " D/M/U=" + androidDownCount + "/" + androidMoveCount + "/" + androidUpCount);
    }

    private void cleanupNativeInk() {
        if (nativeInk != null) {
            try {
                if (started) {
                    nativeInk.stop();
                }
            } catch (Throwable error) {
                Log.w(TAG, "Native stop failed during cleanup", error);
            }
            try {
                nativeInk.destroy();
            } catch (Throwable error) {
                Log.w(TAG, "Native destroy failed during cleanup", error);
            }
        }
        try {
            sendBroadcast(new Intent(ACTION_DISABLE));
        } catch (Throwable error) {
            Log.w(TAG, "Handwriting disable broadcast failed", error);
        }
        nativeInk = null;
        initialized = false;
        started = false;
    }

    @Override
    protected void onPause() {
        cleanupNativeInk();
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        cleanupNativeInk();
        super.onDestroy();
    }

    private final class InkView extends View {
        private final Paint paint = new Paint();
        private Bitmap bitmap;
        private Canvas inkCanvas;
        private final Rect dirty = new Rect();
        private boolean drawing;
        private float lastX, lastY, lastRadius;
        private int regionUpdates;
        private long maxRegionMs;

        InkView() {
            super(MainActivity.this);
            paint.setColor(Color.BLACK);
            setBackgroundColor(Color.WHITE);
        }

        void createBitmap() {
            if (getWidth() == 0 || getHeight() == 0) {
                return;
            }
            bitmap = Bitmap.createBitmap(getWidth(), getHeight(), Bitmap.Config.ARGB_8888);
            bitmap.eraseColor(Color.WHITE);
            inkCanvas = new Canvas(bitmap);
            drawing = false;
            dirty.setEmpty();
        }

        Bitmap getBitmap() {
            return bitmap;
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            if (bitmapPressure && started && event.getPointerCount() == 1
                    && event.getToolType(0) == MotionEvent.TOOL_TYPE_STYLUS) {
                if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
                    regionUpdates = 0;
                    maxRegionMs = 0;
                }
                BufferedStylusInput.dispatch(event, this::drawPressureSample);
                if (!dirty.isEmpty()) {
                    Rect update = new Rect(dirty);
                    dirty.setEmpty();
                    if (update.intersect(0, 0, getWidth(), getHeight())) {
                        long begin = android.os.SystemClock.uptimeMillis();
                        nativeInk.renderRect(update);
                        regionUpdates++;
                        maxRegionMs = Math.max(maxRegionMs,
                                android.os.SystemClock.uptimeMillis() - begin);
                    }
                }
                if (event.getActionMasked() == MotionEvent.ACTION_UP) {
                    Log.i(TAG, "Bitmap pressure stroke updates=" + regionUpdates
                            + " maxRenderRectMs=" + maxRegionMs);
                }
                return true;
            }
            // Both experiment arms own the same gesture. Only this request
            // differs, matching FlutterView's request before touch processing.
            if (unbufferedInput) {
                requestUnbufferedDispatch(event);
            }
            return true;
        }

        private void drawPressureSample(MotionEvent event) {
            int action = event.getActionMasked();
            if (action == MotionEvent.ACTION_CANCEL) {
                drawing = false;
                return;
            }
            if (action == MotionEvent.ACTION_UP) {
                drawing = false;
                return;
            }
            if (action != MotionEvent.ACTION_DOWN && action != MotionEvent.ACTION_MOVE) return;
            float x = event.getX(), y = event.getY();
            float radius = 1 + 6 * Math.max(0, Math.min(1, event.getPressure()));
            if (action == MotionEvent.ACTION_DOWN || !drawing) {
                lastX = x;
                lastY = y;
                lastRadius = radius;
                drawing = true;
            }
            // Independent diagnostic rasterizer, not the vendor's brush code.
            int steps = Math.max(1, (int) Math.ceil(Math.hypot(x - lastX, y - lastY)));
            for (int step = 1; step <= steps; step++) {
                float t = (float) step / steps;
                inkCanvas.drawCircle(lastX + (x - lastX) * t,
                        lastY + (y - lastY) * t,
                        lastRadius + (radius - lastRadius) * t, paint);
            }
            dirty.union((int) Math.floor(Math.min(lastX, x) - 8),
                    (int) Math.floor(Math.min(lastY, y) - 8),
                    (int) Math.ceil(Math.max(lastX, x) + 8),
                    (int) Math.ceil(Math.max(lastY, y) + 8));
            lastX = x;
            lastY = y;
            lastRadius = radius;
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            if (bitmap != null) {
                canvas.drawBitmap(bitmap, 0, 0, paint);
            }
        }
    }
}
