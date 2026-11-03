package dev.local.oneback;

import android.accessibilityservice.AccessibilityService;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.graphics.PixelFormat;
import android.os.Handler;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.view.Gravity;
import android.view.HapticFeedbackConstants;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.WindowManager;
import android.view.accessibility.AccessibilityEvent;

/**
 * Floating Back button.
 *   tap, or swipe starting on the button -> global Back (each can be switched off, Prefs.TAP/SWIPE;
 *                                           swipe directions: Prefs.DIRS, default only horizontal)
 *   long press                           -> button grows, turns blue, shows a move cross
 *     ... then drag                      -> move (position is remembered)
 *     ... then release without dragging  -> hide for a few seconds
 *   landscape                            -> hidden
 * Size, opacity, hide time, style and colors come from {@link Prefs} and are applied live when the
 * settings screen changes them.
 * Uses TYPE_ACCESSIBILITY_OVERLAY, so no "display over other apps" permission is needed.
 */
public class BackService extends AccessibilityService {
    /** Size of the button while armed for moving, so it shows around the thumb. */
    private static final float ARMED_SCALE = 1.6f;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private WindowManager wm;
    private WindowManager.LayoutParams lp;
    private ButtonView button;
    /** Button style (Prefs.STYLE); edge styles snap to the left or right edge. */
    private int style;
    private SharedPreferences prefs;

    /** Top-left corner and size of the button at normal size; lp is derived from these. */
    private int posX, posY, size;
    /** False until the user has moved the button: then the default spot is used (see shownX). */
    private boolean hasPos;

    private float downRawX, downRawY;
    private int startX, startY;
    private boolean pressed, moved, armed, dragging;
    private boolean tapBack, swipeBack; // read on ACTION_DOWN
    private final boolean[] dirBack = new boolean[4]; // left, right, up, down (order of Prefs.DIRS)
    private boolean hiddenByLongPress;
    private float idleAlpha;

    /** Held in a field: SharedPreferences keeps listeners only weakly. */
    private final SharedPreferences.OnSharedPreferenceChangeListener prefListener =
            (p, key) -> applySettings();

    /** Long press: arm for moving and make that visible around the thumb. */
    private final Runnable longPress = () -> {
        armed = true;
        button.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
        button.setArmed(true);
        layout();
    };

    private final Runnable showAgain = this::show;

    @Override
    protected void onServiceConnected() {
        wm = (WindowManager) getSystemService(Context.WINDOW_SERVICE);
        prefs = Prefs.get(this);

        button = new ButtonView(this);
        lp = new WindowManager.LayoutParams(
                0, 0,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT);
        lp.gravity = Gravity.TOP | Gravity.START;
        applySettings();

        final int slop = ViewConfiguration.get(this).getScaledTouchSlop();
        final long longMs = ViewConfiguration.getLongPressTimeout();

        button.setOnTouchListener((v, e) -> {
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    downRawX = e.getRawX();
                    downRawY = e.getRawY();
                    startX = shownX();
                    startY = shownY();
                    pressed = true;
                    moved = armed = dragging = false;
                    tapBack = Prefs.tap(prefs);
                    swipeBack = Prefs.swipe(prefs);
                    for (int i = 0; i < 4; i++) dirBack[i] = Prefs.dir(prefs, Prefs.DIRS[i]);
                    v.setAlpha(1f);
                    handler.postDelayed(longPress, longMs);
                    return true;
                case MotionEvent.ACTION_MOVE: {
                    float dx = e.getRawX() - downRawX, dy = e.getRawY() - downRawY;
                    if (Math.hypot(dx, dy) > slop) {
                        if (armed) dragging = true;      // after long press: move
                        else if (!moved) {               // before: it's a swipe
                            moved = true;
                            handler.removeCallbacks(longPress);
                        }
                    }
                    if (dragging) {
                        posX = startX + Math.round(dx);
                        posY = startY + Math.round(dy);
                        hasPos = true;
                        posX = shownX();   // dragged: keep it where it's drawn
                        posY = shownY();
                        layout();
                    }
                    return true;
                }
                case MotionEvent.ACTION_UP:
                    handler.removeCallbacks(longPress);
                    if (dragging) {
                        prefs.edit().putInt(Prefs.X, posX).putInt(Prefs.Y, posY).apply();
                    } else if (armed) {
                        hide();
                    } else if (moved ? swipeBack && swipeDirOk(e) : tapBack) { // if enabled
                        v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                        performGlobalAction(GLOBAL_ACTION_BACK);
                    }
                    release();
                    return true;
                case MotionEvent.ACTION_CANCEL:
                    handler.removeCallbacks(longPress);
                    release();
                    return true;
            }
            return false;
        });

        updateVisibility();
        wm.addView(button, lp);
        prefs.registerOnSharedPreferenceChangeListener(prefListener);
    }

    /** Direction of the swipe by its dominant axis, checked against the enabled directions. */
    private boolean swipeDirOk(MotionEvent e) {
        float dx = e.getRawX() - downRawX, dy = e.getRawY() - downRawY;
        int dir = Math.abs(dx) >= Math.abs(dy) ? (dx < 0 ? 0 : 1) : (dy < 0 ? 2 : 3);
        return dirBack[dir];
    }

    /** End of a touch: back to normal size, color and opacity. */
    private void release() {
        pressed = false;
        armed = dragging = false;
        button.setArmed(false);
        button.setAlpha(idleAlpha);
        layout();
    }

    private void hide() {
        hiddenByLongPress = true;
        updateVisibility();
        handler.removeCallbacks(showAgain);
        handler.postDelayed(showAgain, Prefs.hideMs(prefs));
    }

    private void show() {
        hiddenByLongPress = false;
        updateVisibility();
    }

    /** Reads size, opacity and position from prefs. A removed position means the default spot. */
    private void applySettings() {
        if (button == null) return;
        DisplayMetrics dm = getResources().getDisplayMetrics();
        size = Math.round(Prefs.sizeDp(prefs) * dm.density);
        hasPos = prefs.contains(Prefs.X) && prefs.contains(Prefs.Y);
        posX = prefs.getInt(Prefs.X, 0);
        posY = prefs.getInt(Prefs.Y, 0);
        idleAlpha = Prefs.alpha(prefs);
        if (!pressed) button.setAlpha(idleAlpha);
        style = Prefs.style(prefs);
        button.setStyle(style);
        button.applyColors(this, prefs);
        layout();
    }

    /** Window height: edge styles are taller than wide, so their glow fits. */
    private int height() {
        return ButtonView.isEdge(style) ? Math.round(size * ButtonView.EDGE_HEIGHT) : size;
    }

    /**
     * Window at the shown position; while armed it is a larger circle around the same centre
     * (for edge styles kept on screen, so the move cross isn't cut off at the edge).
     */
    private void layout() {
        int x = shownX(), y = shownY(), h = height();
        boolean edge = ButtonView.isEdge(style);
        if (edge) button.setRightEdge(x > 0);
        if (armed) {
            int s = Math.round(size * ARMED_SCALE);
            lp.width = lp.height = s;
            lp.x = x + size / 2 - s / 2;
            lp.y = y + h / 2 - s / 2;
            if (edge) {
                int sw = getResources().getDisplayMetrics().widthPixels;
                lp.x = Math.max(0, Math.min(lp.x, sw - s));
            }
        } else {
            lp.width = size;
            lp.height = h;
            lp.x = x;
            lp.y = y;
        }
        if (button.isAttachedToWindow()) wm.updateViewLayout(button, lp);
    }

    /** Visible only in portrait, and not while hidden by a long press. */
    private void updateVisibility() {
        if (button == null) return;
        boolean landscape = getResources().getConfiguration().orientation
                == Configuration.ORIENTATION_LANDSCAPE;
        button.setVisibility(landscape || hiddenByLongPress ? View.GONE : View.VISIBLE);
    }

    /*
     * posX/posY are where the user put the button and are never changed to fit the screen:
     * the shown position is clamped to the current screen instead. Clamping posX/posY itself
     * (up to 1.5) moved the button for good whenever the screen got smaller for a moment,
     * e.g. in landscape (1032 high instead of 2272), so back in portrait it sat mid-screen.
     * Without a saved position the default spot (right edge, 3/4 down) is worked out from the
     * current screen each time, not once at start, so it's right after rotating too.
     * Edge styles snap to the edge nearer to the button's centre (also while dragging).
     */
    private int shownX() {
        DisplayMetrics dm = getResources().getDisplayMetrics();
        int x = hasPos ? posX : dm.widthPixels - size - Math.round(8 * dm.density);
        if (ButtonView.isEdge(style)) return x + size / 2 < dm.widthPixels / 2 ? 0 : dm.widthPixels - size;
        return Math.max(0, Math.min(x, dm.widthPixels - size));
    }

    private int shownY() {
        DisplayMetrics dm = getResources().getDisplayMetrics();
        int y = hasPos ? posY : Math.round(dm.heightPixels * 0.75f);
        return Math.max(0, Math.min(y, dm.heightPixels - height()));
    }

    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        if (button != null) {
            button.applyColors(this, prefs);
            updateVisibility();
            layout();
        }
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) { }

    @Override
    public void onInterrupt() { }

    @Override
    public void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        if (prefs != null) prefs.unregisterOnSharedPreferenceChangeListener(prefListener);
        if (button != null && button.isAttachedToWindow()) wm.removeView(button);
        button = null;
        super.onDestroy();
    }
}
