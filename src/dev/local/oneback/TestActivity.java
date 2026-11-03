package dev.local.oneback;

import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toolbar;

/**
 * Blank page to leave with the floating button, to check that Back works.
 * The toolbar arrow is a fallback that closes the page without OneBack.
 */
public class TestActivity extends ClosingActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        int pad = Math.round(24 * getResources().getDisplayMetrics().density);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setFitsSystemWindows(true); // targetSdk 35 is edge-to-edge: keep clear of the bars

        Toolbar bar = new Toolbar(this);
        bar.setTitle(R.string.test_title);
        bar.setNavigationIcon(R.drawable.ic_back);
        bar.setNavigationContentDescription(R.string.test_close);
        bar.setNavigationOnClickListener(v -> finish());
        root.addView(bar, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        TextView text = new TextView(this);
        text.setText(R.string.test_text);
        text.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        text.setGravity(Gravity.CENTER);
        text.setPadding(pad, pad, pad, pad);
        root.addView(text, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));

        setContentView(root);
    }
}
