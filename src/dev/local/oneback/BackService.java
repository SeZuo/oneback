package dev.local.oneback;

import android.accessibilityservice.AccessibilityService;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.res.Configuration;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
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
 *   tap        -> global Back
 *   drag       -> move (position is remembered)
 *   long press -> hide for HIDE_MS
 *   landscape  -> hidden
 * Uses TYPE_ACCESSIBILITY_OVERLAY, so no "display over other apps" permission is needed.
 */
public class BackService extends AccessibilityService {
    private static final int SIZE_DP = 44;
    private static final long HIDE_MS = 10_000;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private WindowManager wm;
    private WindowManager.LayoutParams lp;
    private View button;
    private SharedPreferences prefs;

    private float downRawX, downRawY;
    private int startX, startY;
    private boolean dragging, longPressed;
    private boolean hiddenByLongPress;

    private final Runnable longPress = () -> {
        longPressed = true;
        button.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
        hiddenByLongPress = true;
        updateVisibility();
        handler.postDelayed(this::show, HIDE_MS);
    };

    @Override
    protected void onServiceConnected() {
        wm = (WindowManager) getSystemService(Context.WINDOW_SERVICE);
        prefs = getSharedPreferences("pos", MODE_PRIVATE);
        DisplayMetrics dm = getResources().getDisplayMetrics();
        int size = Math.round(SIZE_DP * dm.density);

        button = new ArrowView(this);
        lp = new WindowManager.LayoutParams(
                size, size,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                        | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                PixelFormat.TRANSLUCENT);
        lp.gravity = Gravity.TOP | Gravity.START;
        lp.x = prefs.getInt("x", dm.widthPixels - size - Math.round(8 * dm.density));
        lp.y = prefs.getInt("y", Math.round(dm.heightPixels * 0.75f));
        clamp();

        final int slop = ViewConfiguration.get(this).getScaledTouchSlop();
        final long longMs = ViewConfiguration.getLongPressTimeout();

        button.setOnTouchListener((v, e) -> {
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    downRawX = e.getRawX();
                    downRawY = e.getRawY();
                    startX = lp.x;
                    startY = lp.y;
                    dragging = false;
                    longPressed = false;
                    v.setAlpha(1f);
                    handler.postDelayed(longPress, longMs);
                    return true;
                case MotionEvent.ACTION_MOVE: {
                    float dx = e.getRawX() - downRawX, dy = e.getRawY() - downRawY;
                    if (!dragging && !longPressed && Math.hypot(dx, dy) > slop) {
                        dragging = true;
                        handler.removeCallbacks(longPress);
                    }
                    if (dragging) {
                        lp.x = startX + Math.round(dx);
                        lp.y = startY + Math.round(dy);
                        clamp();
                        wm.updateViewLayout(button, lp);
                    }
                    return true;
                }
                case MotionEvent.ACTION_UP:
                    handler.removeCallbacks(longPress);
                    v.setAlpha(0.6f);
                    if (dragging) {
                        prefs.edit().putInt("x", lp.x).putInt("y", lp.y).apply();
                    } else if (!longPressed) {
                        v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                        performGlobalAction(GLOBAL_ACTION_BACK);
                    }
                    return true;
                case MotionEvent.ACTION_CANCEL:
                    handler.removeCallbacks(longPress);
                    v.setAlpha(0.6f);
                    return true;
            }
            return false;
        });

        button.setAlpha(0.6f);
        updateVisibility();
        wm.addView(button, lp);
    }

    private void show() {
        hiddenByLongPress = false;
        updateVisibility();
    }

    /** Visible only in portrait, and not while hidden by a long press. */
    private void updateVisibility() {
        if (button == null) return;
        boolean landscape = getResources().getConfiguration().orientation
                == Configuration.ORIENTATION_LANDSCAPE;
        button.setVisibility(landscape || hiddenByLongPress ? View.GONE : View.VISIBLE);
    }

    /** Keep the button fully on screen (also after rotation). */
    private void clamp() {
        DisplayMetrics dm = getResources().getDisplayMetrics();
        lp.x = Math.max(0, Math.min(lp.x, dm.widthPixels - lp.width));
        lp.y = Math.max(0, Math.min(lp.y, dm.heightPixels - lp.height));
    }

    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
        if (button != null && button.isAttachedToWindow()) {
            updateVisibility();
            clamp();
            wm.updateViewLayout(button, lp);
        }
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) { }

    @Override
    public void onInterrupt() { }

    @Override
    public void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        if (button != null && button.isAttachedToWindow()) wm.removeView(button);
        button = null;
        super.onDestroy();
    }

    /** Dark circle with a white "<" chevron. */
    private static class ArrowView extends View {
        private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Path path = new Path();

        ArrowView(Context c) {
            super(c);
            fill.setColor(0xFF303030);
            stroke.setColor(0xFFFFFFFF);
            stroke.setStyle(Paint.Style.STROKE);
            stroke.setStrokeCap(Paint.Cap.ROUND);
            stroke.setStrokeJoin(Paint.Join.ROUND);
        }

        @Override
        protected void onDraw(Canvas c) {
            float w = getWidth(), h = getHeight(), r = Math.min(w, h) / 2f;
            c.drawCircle(w / 2f, h / 2f, r, fill);
            stroke.setStrokeWidth(r * 0.18f);
            path.reset();
            path.moveTo(w / 2f + r * 0.15f, h / 2f - r * 0.42f);
            path.lineTo(w / 2f - r * 0.27f, h / 2f);
            path.lineTo(w / 2f + r * 0.15f, h / 2f + r * 0.42f);
            c.drawPath(path, stroke);
        }
    }
}
