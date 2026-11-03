package dev.local.oneback;

import android.app.Activity;

/**
 * Base for OneBack's screens: once none of them is visible any more (the user went to the
 * home screen or another app), the whole task closes, so no OneBack window stays in
 * Sailfish's app switcher. Closing that window there force-stops the whole app, accessibility
 * service included, and Android then keeps the service as "malfunctioning" until it's
 * switched off and on.
 */
public abstract class ClosingActivity extends Activity {
    /** OneBack activities between onStart and onStop (all on the main thread). */
    private static int started;

    @Override
    protected void onStart() {
        super.onStart();
        started++;
    }

    @Override
    protected void onStop() {
        super.onStop();
        started--;
        // The next screen's onStart runs before this onStop, so moving between OneBack's own
        // screens never gets here with 0. Rotation recreates the activity: keep it.
        if (started == 0 && !isChangingConfigurations()) {
            finishAndRemoveTask();
        }
    }
}
