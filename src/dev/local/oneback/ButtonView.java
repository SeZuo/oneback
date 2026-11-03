package dev.local.oneback;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.RadialGradient;
import android.graphics.RectF;
import android.graphics.Shader;
import android.os.Build;
import android.view.View;

/**
 * The button, in one of {@link #COUNT} styles. Used by the service and, small, as previews in
 * the settings screen.
 *
 * Free styles are drawn in a square view. Edge styles sit at the left or right screen edge
 * (the service snaps them there) and get a view {@link #EDGE_HEIGHT} times as tall as it is
 * wide, so their glow fits. While armed (long press, moving), every style shows the same
 * larger circle with a four-way cross.
 *
 * Colors: without the system accent, glows are white (like Sailfish's glowing dots) and lines
 * white. With it, the accent (system_accent1_300) takes those parts; the armed circle is
 * system_accent1_700.
 */
final class ButtonView extends View {
    static final int CLASSIC = 0, GLOW_DOT = 1, RING = 2, EDGE_GLOW = 3, DOTS = 4,
            GLOW_CHEVRON = 5, EDGE_TAB = 6, HALFTONE_EDGE = 7, HALFTONE_EDGE_CHEVRON = 8,
            HALFTONE_DISC = 9;
    static final int COUNT = 10;
    static final float EDGE_HEIGHT = 1.5f;

    static boolean isEdge(int style) {
        return style == EDGE_GLOW || style == EDGE_TAB || style == HALFTONE_EDGE
                || style == HALFTONE_EDGE_CHEVRON;
    }

    private static final int CLASSIC_FILL = 0xFF303030, ARMED = 0xFF1E88E5, WHITE = 0xFFFFFFFF,
            BLACK = 0xFF000000, HALFTONE_DARK = 0xFF141414;

    private final Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint stroke = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path path = new Path();
    private final RectF rect = new RectF();
    private int style;
    private boolean armed, rightEdge, useAccent;
    private int accent = WHITE, armedFill = ARMED;

    ButtonView(Context c) {
        super(c);
        stroke.setStyle(Paint.Style.STROKE);
        stroke.setStrokeCap(Paint.Cap.ROUND);
        stroke.setStrokeJoin(Paint.Join.ROUND);
    }

    void setStyle(int s) {
        if (style == s) return;
        style = s;
        invalidate();
    }

    void setArmed(boolean a) {
        if (armed == a) return;
        armed = a;
        invalidate();
    }

    /** Edge styles: which edge the button is at (it then faces into the screen). */
    void setRightEdge(boolean r) {
        if (rightEdge == r) return;
        rightEdge = r;
        invalidate();
    }

    /** Default colors, or Android's system accent if that's switched on (Android 12+). */
    void applyColors(Context c, SharedPreferences prefs) {
        useAccent = Prefs.accent(prefs) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S;
        if (useAccent) {
            accent = c.getColor(android.R.color.system_accent1_300);
            armedFill = c.getColor(android.R.color.system_accent1_700);
        } else {
            accent = WHITE;
            armedFill = ARMED;
        }
        invalidate();
    }

    @Override
    protected void onDraw(Canvas c) {
        float w = getWidth(), h = getHeight();
        if (armed) {
            drawArmed(c, w / 2f, h / 2f, Math.min(w, h) / 2f);
            return;
        }
        int line = useAccent ? accent : WHITE;      // lines and glows
        int dots = useAccent ? accent : HALFTONE_DARK;
        if (isEdge(style)) {
            float r = w / 2f, cy = h / 2f;
            float ex = rightEdge ? w : 0, dir = rightEdge ? -1 : 1;
            switch (style) {
                case EDGE_GLOW:
                    glow(c, ex, cy, r * 1.5f, line, 0.6f);
                    disc(c, ex, cy, r * 0.8f, 0x990D0D0F);
                    chevron(c, ex + dir * r * 0.38f, cy, r * 0.7f, r * 0.1f, WHITE, 0.42f);
                    break;
                case EDGE_TAB: {
                    float tw = r * 1.25f, th = r * 1.6f, rad = r * 0.55f;
                    rect.set(ex - tw, cy - th / 2, ex + tw, cy + th / 2); // other half off-screen
                    fill.setColor(0xBF1F1F21);
                    c.drawRoundRect(rect, rad, rad, fill);
                    stroke.setStrokeWidth(r * 0.05f);
                    stroke.setColor(withAlpha(line, 0.9f));
                    c.drawRoundRect(rect, rad, rad, stroke);
                    chevron(c, ex + dir * tw * 0.5f, cy, r * 0.75f, r * 0.11f, WHITE, 0.42f);
                    break;
                }
                case HALFTONE_EDGE:
                    halftone(c, ex, cy, r * 1.25f, dots, r * 0.13f, 0.35f);
                    break;
                default: // HALFTONE_EDGE_CHEVRON
                    halftone(c, ex, cy, r * 1.25f, dots, r * 0.13f, 0.35f);
                    chevron(c, ex + dir * r * 0.33f, cy, r * 0.65f, r * 0.1f, WHITE, 0.42f);
            }
            return;
        }
        float R = Math.min(w, h) / 2f, cx = w / 2f, cy = h / 2f;
        switch (style) {
            case GLOW_DOT: {
                float r = R / 1.25f;
                glow(c, cx, cy, r * 1.25f, line, 0.55f);
                disc(c, cx, cy, r * 0.62f, 0x8C0D0D0F);
                chevron(c, cx, cy, r * 0.75f, r * 0.11f, WHITE, 0.42f);
                break;
            }
            case RING:
                disc(c, cx, cy, R, 0x59000000);
                stroke.setStrokeWidth(R * 0.06f);
                stroke.setColor(withAlpha(line, 0.9f));
                c.drawCircle(cx, cy, R * 0.92f, stroke);
                chevron(c, cx, cy, R, R * 0.07f, line, 0.38f);
                break;
            case DOTS: {
                disc(c, cx, cy, R, 0x99141417);
                float[][] pts = { {0.18f, -0.42f}, {0.04f, -0.28f}, {-0.11f, -0.14f}, {-0.25f, 0},
                        {-0.11f, 0.14f}, {0.04f, 0.28f}, {0.18f, 0.42f} };
                for (float[] p : pts) {
                    float x = cx + p[0] * R, y = cy + p[1] * R;
                    glow(c, x, y, R * 0.16f, line, 0.7f);
                    disc(c, x, y, R * 0.055f, WHITE);
                }
                break;
            }
            case GLOW_CHEVRON: {
                // Without the accent the glow is a dark shadow, so the white chevron also
                // shows on light pages.
                int g = useAccent ? accent : BLACK;
                float[][] layers = { {0.45f, 0.08f}, {0.3f, 0.15f}, {0.2f, 0.25f} };
                for (float[] l : layers) chevron(c, cx, cy, R * 1.1f, R * l[0], withAlpha(g, l[1]), 0.42f);
                chevron(c, cx, cy, R * 1.1f, R * 0.11f, WHITE, 0.42f);
                break;
            }
            case HALFTONE_DISC: {
                float r = R / 1.15f;
                halftone(c, cx, cy, r * 1.15f, dots, r * 0.12f, 0.5f);
                chevron(c, cx, cy, r * 0.9f, r * 0.11f, WHITE, 0.42f);
                break;
            }
            default: // CLASSIC
                disc(c, cx, cy, R, CLASSIC_FILL);
                chevron(c, cx, cy, R, R * 0.18f, line, 0.42f);
        }
    }

    /** Larger circle with a four-way move cross (same for every style). */
    private void drawArmed(Canvas c, float cx, float cy, float r) {
        disc(c, cx, cy, r, armedFill);
        stroke.setColor(WHITE);
        stroke.setStrokeWidth(r * 0.1f);
        float a = r * 0.55f, head = r * 0.15f;
        path.reset();
        path.moveTo(cx - a, cy); path.lineTo(cx + a, cy);
        path.moveTo(cx, cy - a); path.lineTo(cx, cy + a);
        // arrow heads: left, right, up, down
        path.moveTo(cx - a + head, cy - head); path.lineTo(cx - a, cy); path.lineTo(cx - a + head, cy + head);
        path.moveTo(cx + a - head, cy - head); path.lineTo(cx + a, cy); path.lineTo(cx + a - head, cy + head);
        path.moveTo(cx - head, cy - a + head); path.lineTo(cx, cy - a); path.lineTo(cx + head, cy - a + head);
        path.moveTo(cx - head, cy + a - head); path.lineTo(cx, cy + a); path.lineTo(cx + head, cy + a - head);
        c.drawPath(path, stroke);
    }

    /** "<" pointing left, centred on cx/cy; k = half height relative to r. */
    private void chevron(Canvas c, float cx, float cy, float r, float lw, int color, float k) {
        stroke.setStrokeWidth(lw);
        stroke.setColor(color);
        path.reset();
        path.moveTo(cx + r * 0.15f, cy - r * k);
        path.lineTo(cx - r * 0.27f, cy);
        path.lineTo(cx + r * 0.15f, cy + r * k);
        c.drawPath(path, stroke);
    }

    private void disc(Canvas c, float x, float y, float r, int color) {
        fill.setColor(color);
        c.drawCircle(x, y, r, fill);
    }

    /** Soft round glow, alpha a in the centre fading to nothing at radius r. */
    private void glow(Canvas c, float x, float y, float r, int color, float a) {
        fill.setShader(new RadialGradient(x, y, r, withAlpha(color, a), withAlpha(color, 0),
                Shader.TileMode.CLAMP));
        c.drawCircle(x, y, r, fill);
        fill.setShader(null);
    }

    /**
     * Dot grid turned 45 degrees: full-size dots up to core (relative to r), then smaller
     * and smaller out to r. Dots outside the view are clipped, which gives the half disc at an
     * edge.
     */
    private void halftone(Canvas c, float cx, float cy, float r, int color, float step, float core) {
        fill.setColor(color);
        int n = (int) (r * 1.5f / step) + 2;
        for (int i = -n; i <= n; i++) {
            for (int j = -n; j <= n; j++) {
                float x = cx + (i + j) * step / 2f, y = cy + (i - j) * step / 2f;
                float d = (float) Math.hypot(x - cx, y - cy) / r;
                if (d > 1) continue;
                float k = d < core ? 1 : (float) Math.pow(1 - (d - core) / (1 - core), 1.3);
                float rad = step * 0.72f * k;
                if (rad < 0.4f) continue;
                c.drawCircle(x, y, rad, fill);
            }
        }
    }

    private static int withAlpha(int color, float a) {
        return (Math.round(a * 255) << 24) | (color & 0xFFFFFF);
    }
}
