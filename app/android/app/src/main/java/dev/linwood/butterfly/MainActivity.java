package dev.linwood.butterfly;

import android.content.Intent;
import android.net.Uri;
import android.util.Log;
import android.view.MotionEvent;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.io.IOException;
import java.io.InputStream;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.util.Map;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.plugin.common.MethodChannel;


public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "linwood.dev/butterfly";
    private static final String NATIVE_INK_CHANNEL = "linwood.dev/butterfly/native_ink";
    private static final String NATIVE_INK_CONTROLLER =
            "dev.linwood.butterfly.magicpie.MagicpieNativeInkController";
    private static final String NATIVE_INK_TAG = "MagicpieNativeInk";
    private String intentType = null;
    private byte[] intentData = null;
    private Object nativeInkController;
    private Method nativeInkPrepare;
    private Method nativeInkPresent;
    private Method nativeInkDispose;
    private Method nativeInkMotionEvent;

    @Override
    @Nullable
    public String getInitialRoute() {
        if (handleIntent(getIntent())) {
            return "/intent";
        }
        return super.getInitialRoute();
    }

    @Override
    protected void onNewIntent(@NonNull Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (handleIntent(intent) && getFlutterEngine() != null) {
            getFlutterEngine().getNavigationChannel().pushRoute("/intent");
        }
    }

    private boolean handleIntent(Intent intent) {
        String action = intent.getAction();
        String type = intent.getType();

        if (Intent.ACTION_VIEW.equals(action) || Intent.ACTION_EDIT.equals(action) || Intent.ACTION_SEND.equals(action)) {
            Uri uri = intent.getData();
            if (uri == null) {
                uri = intent.getParcelableExtra(Intent.EXTRA_STREAM);
            }
            if (uri == null && intent.getClipData() != null && intent.getClipData().getItemCount() > 0) {
                uri = intent.getClipData().getItemAt(0).getUri();
            }
            if (uri != null) {
                if (type == null) {
                    type = getContentResolver().getType(uri);
                }
                if (type == null) {
                    type = "application/octet-stream";
                }
                intentType = type;
                try {
                    InputStream inputStream = getContentResolver().openInputStream(uri);
                    if (inputStream != null) {
                        intentData = getBytes(inputStream);
                        inputStream.close();
                        return true;
                    }
                } catch (IOException e) {
                    e.printStackTrace();
                    intentData = null;
                    intentType = null;
                }
            } else if (Intent.ACTION_SEND.equals(action) && intent.hasExtra(Intent.EXTRA_TEXT)) {
                String text = intent.getStringExtra(Intent.EXTRA_TEXT);
                if (text != null) {
                    intentType = type != null ? type : "text/plain";
                    intentData = text.getBytes(StandardCharsets.UTF_8);
                    return true;
                }
            }
        }
        return false;
    }

    private byte[] getBytes(InputStream inputStream) throws IOException {
        java.io.ByteArrayOutputStream byteBuffer = new java.io.ByteArrayOutputStream();
        int bufferSize = 1024;
        byte[] buffer = new byte[bufferSize];
        int len;
        while ((len = inputStream.read(buffer)) != -1) {
            byteBuffer.write(buffer, 0, len);
        }
        return byteBuffer.toByteArray();
    }

    @Override
    public void configureFlutterEngine(@NonNull io.flutter.embedding.engine.FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler(
                        (call, result) -> {
                            if (call.method.equals("isMagicPie")) {
                                result.success(android.os.Build.DEVICE.equals("px30_eink_magicpie")
                                        || android.os.Build.MODEL.equalsIgnoreCase("Magicpie M1"));
                            } else if (call.method.equals("getIntentType")) {
                                result.success(intentType);
                            } else if (call.method.equals("getIntentData")) {
                                result.success(intentData);
                            } else {
                                result.notImplemented();
                            }
                        }
                );
        initializeNativeInkController();
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), NATIVE_INK_CHANNEL)
                .setMethodCallHandler(
                        (call, result) -> {
                            if (nativeInkController == null) {
                                result.success(false);
                                return;
                            }
                            if (call.method.equals("prepare")) {
                                if (!(call.arguments instanceof Map)) {
                                    result.success(false);
                                    return;
                                }
                                invokeNativeInkAsync(nativeInkPrepare, call.arguments, result);
                            } else if (call.method.equals("present")) {
                                invokeNativeInkAsync(nativeInkPresent, result);
                            } else if (call.method.equals("dispose")) {
                                result.success(invokeNativeInkBoolean(nativeInkDispose));
                            } else {
                                result.notImplemented();
                            }
                        }
                );
    }

    private void initializeNativeInkController() {
        if (android.os.Build.VERSION.SDK_INT != 27
                || !(android.os.Build.DEVICE.equals("px30_eink_magicpie")
                || android.os.Build.MODEL.equalsIgnoreCase("Magicpie M1"))) {
            return;
        }
        try {
            Class<?> controllerClass = Class.forName(NATIVE_INK_CONTROLLER);
            nativeInkController = controllerClass.getConstructor(android.app.Activity.class)
                    .newInstance(this);
            nativeInkPrepare = controllerClass.getMethod(
                    "prepare", Map.class, MethodChannel.Result.class);
            nativeInkPresent = controllerClass.getMethod("present", MethodChannel.Result.class);
            nativeInkDispose = controllerClass.getMethod("dispose");
            nativeInkMotionEvent = controllerClass.getMethod("onMotionEvent", MotionEvent.class);
        } catch (ClassNotFoundException ignored) {
            // Expected for non-magicpie product flavors.
        } catch (ReflectiveOperationException error) {
            nativeInkController = null;
            Log.w(NATIVE_INK_TAG, "Native ink controller unavailable", unwrap(error));
        }
    }

    private void invokeNativeInkAsync(Method method, Object... arguments) {
        if (method == null || nativeInkController == null) {
            MethodChannel.Result result = (MethodChannel.Result) arguments[arguments.length - 1];
            result.success(false);
            return;
        }
        try {
            method.invoke(nativeInkController, arguments);
        } catch (ReflectiveOperationException error) {
            Log.w(NATIVE_INK_TAG, "Native ink call failed", unwrap(error));
            MethodChannel.Result result = (MethodChannel.Result) arguments[arguments.length - 1];
            result.success(false);
        }
    }

    private boolean invokeNativeInkBoolean(Method method) {
        if (method == null || nativeInkController == null) {
            return false;
        }
        try {
            return Boolean.TRUE.equals(method.invoke(nativeInkController));
        } catch (ReflectiveOperationException error) {
            Log.w(NATIVE_INK_TAG, "Native ink call failed", unwrap(error));
            return false;
        }
    }

    private Throwable unwrap(ReflectiveOperationException error) {
        if (error instanceof InvocationTargetException
                && ((InvocationTargetException) error).getCause() != null) {
            return ((InvocationTargetException) error).getCause();
        }
        return error;
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent event) {
        if (nativeInkController != null && nativeInkMotionEvent != null) {
            try {
                nativeInkMotionEvent.invoke(nativeInkController, event);
            } catch (ReflectiveOperationException error) {
                Log.w(NATIVE_INK_TAG, "Native ink event audit failed", unwrap(error));
            }
        }
        return super.dispatchTouchEvent(event);
    }

    @Override
    protected void onPause() {
        invokeNativeInkBoolean(nativeInkDispose);
        super.onPause();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        if (!hasFocus) {
            invokeNativeInkBoolean(nativeInkDispose);
        }
        super.onWindowFocusChanged(hasFocus);
    }

    @Override
    protected void onDestroy() {
        invokeNativeInkBoolean(nativeInkDispose);
        super.onDestroy();
    }
}
