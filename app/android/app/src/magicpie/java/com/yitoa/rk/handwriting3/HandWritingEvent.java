package com.yitoa.rk.handwriting3;

import androidx.annotation.Keep;

/** A single event reported by the device-provided handwriting library. */
@Keep
public final class HandWritingEvent {
    public static final int ACTION_DOWN = 0;
    public static final int ACTION_UP = 1;
    public static final int ACTION_MOVE = 2;

    private int toolType;
    private int buttonState;
    private int action = -1;
    private float x;
    private float y;
    private float pressure;
    private boolean valid;

    public int getToolType() {
        return toolType;
    }

    public int getButtonState() {
        return buttonState;
    }

    public int getAction() {
        return action;
    }

    public float getX() {
        return x;
    }

    public float getY() {
        return y;
    }

    public float getPressure() {
        return pressure;
    }

    public boolean isValid() {
        return valid;
    }

    void setToolType(int toolType) {
        this.toolType = toolType;
    }

    void setButtonState(int buttonState) {
        this.buttonState = buttonState;
    }

    void setAction(int action) {
        this.action = action;
    }

    void setX(float x) {
        this.x = x;
    }

    void setY(float y) {
        this.y = y;
    }

    void setPressure(float pressure) {
        this.pressure = pressure;
    }

    void setValid(boolean valid) {
        this.valid = valid;
    }
}
