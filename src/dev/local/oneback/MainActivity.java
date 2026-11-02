package dev.local.oneback;

import android.animation.ObjectAnimator;
import android.animation.PropertyValuesHolder;
import android.animation.ValueAnimator;
import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.provider.Settings;
import android.text.TextUtils;
import android.util.Log;
import android.util.TypedValue;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.Switch;
import android.widget.TextView;

/**
 * Settings screen: service status (with a shortcut to Android's accessibility settings),
 * a test page, gesture mode, button size, opacity, hide time, and resetting the position. Values are written to
 * {@link Prefs} and the running service picks them up immediately.
 */
public class MainActivity extends Activity {
    private SharedPreferences prefs;
    private TextView status;
    private Button toggle;
    private ObjectAnimator pulse;
    private static final String TAG = "OneBack";

    /**
     * The theme's own button background, kept untouched and put back when the warning goes away.
     * (Its grey is a tint inside the drawable, so tinting the view would lose it.)
     */
    private ColorStateList toggleTextColors;
    private Drawable toggleBg;

    /** Amber: readable as a warning on both light and dark themes. */
    private static final int WARN = 0xFFFFB300;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Log.i(TAG, "settings screen created");
        prefs = Prefs.get(this);

        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(16);
        col.setPadding(pad, pad, pad, pad);

        TextView title = text(getString(R.string.app_name), 24);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        col.addView(title);

        status = text("", 16);
        LinearLayout.LayoutParams statusLp = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        statusLp.setMargins(0, dp(16), 0, dp(8));
        col.addView(status, statusLp);

        toggle = new Button(this);
        // NEW_TASK: open Android Settings as its own app. Inside OneBack's task it would stay on
        // top, and tapping the OneBack icon would bring back Settings instead of this screen
        // (Sailfish waits for a OneBack window, times out and closes).
        toggle.setOnClickListener(v -> startActivity(
                new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)));
        col.addView(toggle);
        toggleTextColors = toggle.getTextColors();
        toggleBg = toggle.getBackground();
        col.setClipToPadding(false); // let the pulsing button grow into the side padding
        pulse = ObjectAnimator.ofPropertyValuesHolder(toggle,
                PropertyValuesHolder.ofFloat(View.SCALE_X, 1f, 1.04f),
                PropertyValuesHolder.ofFloat(View.SCALE_Y, 1f, 1.04f));
        pulse.setDuration(700);
        pulse.setRepeatCount(ValueAnimator.INFINITE);
        pulse.setRepeatMode(ValueAnimator.REVERSE);

        Button test = new Button(this);
        test.setText(R.string.open_test);
        test.setOnClickListener(v -> startActivity(new Intent(this, TestActivity.class)));
        col.addView(test);

        col.addView(heading(R.string.heading_gestures));
        Switch swipe = new Switch(this);
        swipe.setText(R.string.label_swipe);
        swipe.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        swipe.setPadding(0, dp(12), 0, dp(4));
        TextView modeHelp = text("", 14);
        modeHelp.setAlpha(0.7f);
        boolean swipeOn = prefs.getBoolean(Prefs.SWIPE, false);
        swipe.setChecked(swipeOn);
        modeHelp.setText(swipeOn ? R.string.help_swipe : R.string.help_tap);
        swipe.setOnCheckedChangeListener((b, on) -> {
            prefs.edit().putBoolean(Prefs.SWIPE, on).apply();
            modeHelp.setText(on ? R.string.help_swipe : R.string.help_tap);
        });
        col.addView(swipe);
        col.addView(modeHelp);

        col.addView(heading(R.string.heading_button));
        addSlider(col, R.string.label_size, R.string.unit_dp, Prefs.SIZE,
                Prefs.SIZE_MIN, Prefs.SIZE_MAX, Prefs.SIZE_STEP, Prefs.SIZE_DEF);
        addSlider(col, R.string.label_opacity, R.string.unit_percent, Prefs.ALPHA,
                Prefs.ALPHA_MIN, Prefs.ALPHA_MAX, Prefs.ALPHA_STEP, Prefs.ALPHA_DEF);
        addSlider(col, R.string.label_hide, R.string.unit_seconds, Prefs.HIDE,
                Prefs.HIDE_MIN, Prefs.HIDE_MAX, Prefs.HIDE_STEP, Prefs.HIDE_DEF);

        TextView hint = text(getString(R.string.hint_live), 14);
        hint.setAlpha(0.7f);
        hint.setPadding(0, dp(4), 0, dp(16));
        col.addView(hint);

        Button resetPos = new Button(this);
        resetPos.setText(R.string.reset_position);
        resetPos.setOnClickListener(v ->
                prefs.edit().remove(Prefs.X).remove(Prefs.Y).apply());
        col.addView(resetPos);

        Button defaults = new Button(this);
        defaults.setText(R.string.reset_defaults);
        defaults.setOnClickListener(v -> {
            prefs.edit().remove(Prefs.SIZE).remove(Prefs.ALPHA).remove(Prefs.HIDE)
                    .remove(Prefs.SWIPE).apply();
            recreate();
        });
        col.addView(defaults);

        ScrollView scroll = new ScrollView(this);
        scroll.setFitsSystemWindows(true); // targetSdk 35 is edge-to-edge: keep clear of the bars
        scroll.addView(col);
        setContentView(scroll);
    }

    @Override
    protected void onResume() {
        super.onResume();
        boolean on = serviceEnabled();
        Log.i(TAG, "settings screen resumed, service on=" + on);
        status.setText(on ? R.string.status_on : R.string.status_off);
        toggle.setText(on ? R.string.open_settings_off : R.string.open_settings_on);
        try {
            applyWarning(on);
        } catch (RuntimeException e) {
            Log.e(TAG, "styling failed", e); // never let the styling stop the screen
        }
    }

    /** Off: amber box around the status, amber pulsing button. On: theme defaults. */
    private void applyWarning(boolean on) {
        if (on) {
            status.setBackground(null);
            status.setPadding(0, 0, 0, 0);         // align with the headings below
            toggle.setBackground(toggleBg);
            toggle.setTextColor(toggleTextColors);
            stopPulse();
        } else {
            int boxPad = dp(12);
            status.setPadding(boxPad, boxPad, boxPad, boxPad);
            GradientDrawable box = new GradientDrawable();
            box.setColor(0x33FFB300);              // 20 % amber fill
            box.setStroke(dp(2), WARN);
            box.setCornerRadius(dp(8));
            status.setBackground(box);
            GradientDrawable warnBg = new GradientDrawable();
            warnBg.setColor(WARN);
            warnBg.setCornerRadius(dp(4));
            toggle.setBackground(warnBg);
            toggle.setTextColor(0xFF000000);
            if (!pulse.isStarted()) pulse.start();
        }
    }

    @Override
    protected void onPause() {
        super.onPause();
        stopPulse(); // restarted in onResume if still off
    }

    private void stopPulse() {
        pulse.cancel();
        toggle.setScaleX(1f);
        toggle.setScaleY(1f);
    }

    /** True if BackService is in the enabled accessibility services list. */
    private boolean serviceEnabled() {
        String list = Settings.Secure.getString(getContentResolver(),
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        if (TextUtils.isEmpty(list)) return false;
        ComponentName me = new ComponentName(this, BackService.class);
        for (String s : list.split(":")) {
            if (me.equals(ComponentName.unflattenFromString(s))) return true;
        }
        return false;
    }

    private void addSlider(LinearLayout col, int labelRes, int unitRes, String key,
                           int min, int max, int step, int def) {
        TextView label = text("", 16);
        label.setPadding(0, dp(12), 0, 0);
        SeekBar bar = new SeekBar(this);
        bar.setMax((max - min) / step);
        int value = Prefs.clamp(prefs.getInt(key, def), min, max);
        bar.setProgress((value - min) / step);
        setLabel(label, labelRes, unitRes, value);
        bar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar b, int progress, boolean fromUser) {
                int v = min + progress * step;
                setLabel(label, labelRes, unitRes, v);
                if (fromUser) prefs.edit().putInt(key, v).apply();
            }
            @Override public void onStartTrackingTouch(SeekBar b) { }
            @Override public void onStopTrackingTouch(SeekBar b) { }
        });
        col.addView(label);
        col.addView(bar);
    }

    private void setLabel(TextView t, int labelRes, int unitRes, int value) {
        t.setText(getString(labelRes) + ": " + getString(unitRes, value));
    }

    private TextView heading(int res) {
        TextView t = text(getString(res), 14);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setAllCaps(true);
        t.setPadding(0, dp(24), 0, 0);
        return t;
    }

    private TextView text(String s, int sp) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        return t;
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }
}
