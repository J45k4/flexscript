package org.flexscript.collie;

import android.app.Activity;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.graphics.Insets;
import android.view.*;
import android.widget.*;
import org.json.JSONObject;

/** Native conversation permissions, persisted before a switch reports success. */
final class PermissionsPage extends LinearLayout {
    interface Change { boolean set(String key, boolean allowed); }
    private final Activity activity;
    private final TextView summary;
    private int enabled;
    private static final String[] TITLES = {"Internet access", "Read workspace files",
        "Write workspace files", "Read database", "Write database", "Read past messages"};
    private static final String[] DETAILS = {
        "Fetch web pages and APIs over HTTPS. Your ChatGPT connection stays available when this is off.",
        "Read files, list folders, and view text or images in this conversation’s private workspace.",
        "Create folders and create or replace workspace files.",
        "Read tables, columns and saved rows in this conversation’s FlexDB.",
        "Create tables, change schemas, and add, update or delete saved rows.",
        "Query archived messages, previous programs and their results from Flexscript."};

    PermissionsPage(Activity owner, CollieUi ui, JSONObject grants, Runnable back, Change change) {
        super(owner);
        activity = owner;
        setOrientation(VERTICAL);
        setBackgroundColor(CollieUi.BG);
        if (Build.VERSION.SDK_INT >= 28) setAccessibilityPaneTitle("Permissions");
        if (Build.VERSION.SDK_INT >= 30)
            setOnApplyWindowInsetsListener((v, insets) -> {
                Insets bars = insets.getInsets(WindowInsets.Type.systemBars());
                v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
                return insets;
            });
        else setOnApplyWindowInsetsListener((v, insets) -> {
            v.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(),
                insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            return insets;
        });
        LinearLayout header = new LinearLayout(owner);
        header.setGravity(Gravity.CENTER_VERTICAL);
        header.setPadding(dp(10), dp(12), dp(18), dp(10));
        header.addView(ui.navigationButton("back", "Back to conversation", back), new LayoutParams(dp(46), dp(46)));
        TextView title = text("Permissions", 23, CollieUi.TEXT);
        title.setTypeface(Typeface.create("sans-serif-medium", 0));
        title.setPadding(dp(6), 0, 0, 0);
        header.addView(title);
        addView(header);
        summary = text("", 13, CollieUi.ACCENT);
        summary.setPadding(dp(22), 0, dp(22), dp(16));
        addView(summary);
        ScrollView scroll = new ScrollView(owner);
        scroll.setFillViewport(true);
        scroll.setClipToPadding(false);
        addView(scroll, new LayoutParams(-1, 0, 1));
        LinearLayout content = new LinearLayout(owner);
        content.setOrientation(VERTICAL);
        content.setPadding(dp(18), 0, dp(18), dp(24));
        scroll.addView(content, new ScrollView.LayoutParams(-1, -2));
        TextView intro = text("Choose what Collie can access in this conversation.", 15, CollieUi.MUTED);
        intro.setPadding(dp(4), 0, dp(4), dp(18));
        content.addView(intro);
        for (int i = 0; i < AgentPermissions.KEYS.length; i++) {
            String key = AgentPermissions.KEYS[i];
            boolean allowed = grants.optBoolean(key, false);
            if (allowed) enabled++;
            LinearLayout row = new LinearLayout(owner);
            row.setGravity(Gravity.CENTER_VERTICAL);
            row.setPadding(dp(16), dp(15), dp(12), dp(15));
            GradientDrawable shape = new GradientDrawable();
            shape.setColor(CollieUi.SURFACE);
            shape.setCornerRadius(dp(16));
            shape.setStroke(dp(1), CollieUi.BORDER);
            row.setBackground(shape);
            LayoutParams rowParams = new LayoutParams(-1, -2);
            rowParams.bottomMargin = dp(10);
            content.addView(row, rowParams);
            LinearLayout labels = new LinearLayout(owner);
            labels.setOrientation(VERTICAL);
            labels.setPadding(0, 0, dp(10), 0);
            TextView name = text(TITLES[i], 16, CollieUi.TEXT);
            name.setTypeface(Typeface.create("sans-serif-medium", 0));
            labels.addView(name);
            TextView detail = text(DETAILS[i], 13, CollieUi.MUTED);
            detail.setPadding(0, dp(6), 0, 0);
            detail.setLineSpacing(dp(2), 1);
            labels.addView(detail);
            row.addView(labels, new LayoutParams(0, -2, 1));
            Switch toggle = new Switch(owner);
            toggle.setContentDescription(TITLES[i]);
            toggle.setChecked(allowed);
            toggle.setShowText(false);
            toggle.setMinHeight(dp(48));
            toggle.setThumbTintList(new ColorStateList(new int[][] {
                {android.R.attr.state_checked}, {}}, new int[] {CollieUi.ACCENT, CollieUi.MUTED}));
            toggle.setTrackTintList(new ColorStateList(new int[][] {
                {android.R.attr.state_checked}, {}}, new int[] {0xff536a47, CollieUi.BORDER}));
            row.addView(toggle);
            row.setOnClickListener(v -> toggle.performClick());
            toggle.setOnCheckedChangeListener((button, checked) -> {
                if (button.getTag() != null) return;
                if (change.set(key, checked)) {
                    enabled += checked ? 1 : -1;
                    updateSummary();
                } else {
                    button.setTag(Boolean.TRUE);
                    button.setChecked(!checked);
                    button.setTag(null);
                }
            });
        }
        TextView note = text("Saved automatically for this conversation. Turning access off blocks future program calls; it does not erase information already in the chat.", 12, CollieUi.MUTED);
        note.setPadding(dp(4), dp(10), dp(4), dp(16));
        note.setLineSpacing(dp(3), 1);
        content.addView(note);
        TextView privateNote = text("Login credentials, other apps, shared storage, USB and host processes remain unavailable to programs.", 12, CollieUi.MUTED);
        privateNote.setPadding(dp(4), 0, dp(4), 0);
        privateNote.setLineSpacing(dp(3), 1);
        content.addView(privateNote);
        updateSummary();
    }
    private void updateSummary() { summary.setText(enabled + " of 6 permissions enabled"); }
    private int dp(int n) { return (int)(n * activity.getResources().getDisplayMetrics().density + .5f); }
    private TextView text(String value, int size, int color) {
        TextView view = new TextView(activity);
        view.setText(value);view.setTextSize(size);view.setTextColor(color);
        return view;
    }
}
