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

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

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
        int count = nativeEventCount;
        int action = event.getAction();
        float x = event.getX();
        float y = event.getY();
        if (action == HandWritingEvent.ACTION_UP || count % 25 == 0) {
            Log.i(TAG, "native event action=" + action + " x=" + x + " y=" + y);
            runOnUiThread(() -> showStatus("Native ink running"));
        }
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent event) {
        int toolType = event.getToolType(0);
        if (toolType == MotionEvent.TOOL_TYPE_STYLUS
                || toolType == MotionEvent.TOOL_TYPE_ERASER) {
            androidStylusEventCount++;
            int action = event.getActionMasked();
            if (action == MotionEvent.ACTION_UP || androidStylusEventCount % 25 == 0) {
                Log.i(TAG, "Android stylus event action=" + action
                        + " x=" + event.getX() + " y=" + event.getY());
                showStatus(started ? "Native ink running" : "Stopped");
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
        status.setText("Public system library only - " + message
                + "\nnativeEvents=" + nativeEventCount
                + ", androidStylusEvents=" + androidStylusEventCount);
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
        }

        Bitmap getBitmap() {
            return bitmap;
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
