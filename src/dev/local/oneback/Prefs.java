package dev.local.oneback;

import android.content.Context;
import android.content.SharedPreferences;

/** Settings shared by the service and the settings screen (same process, so changes apply live). */
final class Prefs {
    /** File name kept from 1.x, so a saved button position survives the update. */
    static final String FILE = "pos";

    static final String X = "x", Y = "y";
    static final String SIZE = "size_dp", ALPHA = "alpha_pct", HIDE = "hide_s";
    /** false: tap = Back, drag = move. true: swipe = Back, long press + drag = move. */
    static final String SWIPE = "swipe_mode";

    static final int SIZE_DEF = 44, SIZE_MIN = 28, SIZE_MAX = 80, SIZE_STEP = 2;
    static final int ALPHA_DEF = 60, ALPHA_MIN = 20, ALPHA_MAX = 100, ALPHA_STEP = 5;
    static final int HIDE_DEF = 10, HIDE_MIN = 2, HIDE_MAX = 60, HIDE_STEP = 1;

    private Prefs() { }

    static SharedPreferences get(Context c) {
        return c.getSharedPreferences(FILE, Context.MODE_PRIVATE);
    }

    static int sizeDp(SharedPreferences p) { return clamp(p.getInt(SIZE, SIZE_DEF), SIZE_MIN, SIZE_MAX); }
    static float alpha(SharedPreferences p) { return clamp(p.getInt(ALPHA, ALPHA_DEF), ALPHA_MIN, ALPHA_MAX) / 100f; }
    static long hideMs(SharedPreferences p) { return clamp(p.getInt(HIDE, HIDE_DEF), HIDE_MIN, HIDE_MAX) * 1000L; }

    static int clamp(int v, int min, int max) { return Math.max(min, Math.min(v, max)); }
}
