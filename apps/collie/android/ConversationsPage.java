package org.flexscript.collie;

import android.app.Activity;
import android.content.res.ColorStateList;
import android.graphics.Insets;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.Build;
import android.text.Editable;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.widget.*;
import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.function.Consumer;

/** A full conversation browser. ListView recycles rows even for large histories. */
final class ConversationsPage extends LinearLayout {
    static final class Entry {
        final String id, title, preview;
        final long updated;
        final boolean current;
        Entry(String id, String title, String preview, long updated, boolean current) {
            this.id = id;
            this.title = title;
            this.preview = preview;
            this.updated = updated;
            this.current = current;
        }
    }
    private final Activity activity;
    private final TextView count, emptyTitle, emptyBody;
    private final EditText search;
    private final ListView list;
    private final LinearLayout empty;
    private final ArrayList<Entry> all = new ArrayList<>(), shown = new ArrayList<>();
    private final Adapter adapter = new Adapter();
    private boolean loading = true;

    ConversationsPage(
        Activity owner, CollieUi ui, Runnable back, Runnable newChat, Consumer<String> open) {
        super(owner);
        activity = owner;
        setOrientation(VERTICAL);
        setBackgroundColor(CollieUi.BG);
        setFocusableInTouchMode(true);
        if (Build.VERSION.SDK_INT >= 28)
            setAccessibilityPaneTitle("Conversations");
        if (Build.VERSION.SDK_INT >= 30)
            setOnApplyWindowInsetsListener((v, insets) -> {
                Insets bars = insets.getInsets(WindowInsets.Type.systemBars());
                v.setPadding(bars.left, bars.top, bars.right,
                    Math.max(bars.bottom, insets.getInsets(WindowInsets.Type.ime()).bottom));
                return insets;
            });
        else
            setOnApplyWindowInsetsListener((v, insets) -> {
                v.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(),
                    insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
                return insets;
            });
        LinearLayout header = row();
        header.setPadding(dp(10), dp(12), dp(14), dp(10));
        header.addView(ui.navigationButton("back", "Back to conversation", back), params(46, 46));
        TextView title = label("Conversations", 23, CollieUi.TEXT);
        title.setTypeface(Typeface.create("sans-serif-medium", 0));
        title.setPadding(dp(6), 0, 0, 0);
        header.addView(title, new LayoutParams(0, -2, 1));
        header.addView(ui.navigationButton("plus", "New conversation", newChat), params(46, 46));
        addView(header);
        count = label("Loading conversations…", 12, CollieUi.MUTED);
        count.setPadding(dp(22), 0, dp(22), dp(18));
        addView(count);
        LinearLayout searchBox = row();
        searchBox.setPadding(dp(10), dp(2), dp(6), dp(2));
        searchBox.setBackground(background(CollieUi.SURFACE, 16, CollieUi.BORDER));
        View icon = ui.navigationButton("search", "", () -> {});
        icon.setClickable(false);
        icon.setFocusable(false);
        icon.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        searchBox.addView(icon, params(30, 40));
        search = new EditText(owner);
        search.setSingleLine(true);
        search.setTextColor(CollieUi.TEXT);
        search.setHintTextColor(CollieUi.MUTED);
        search.setTextSize(15);
        search.setHint("Search conversations");
        search.setContentDescription("Search conversations");
        search.setBackgroundColor(android.graphics.Color.TRANSPARENT);
        search.setPadding(dp(6), dp(12), dp(4), dp(12));
        search.setInputType(android.text.InputType.TYPE_CLASS_TEXT
            | android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES);
        search.setImeOptions(android.view.inputmethod.EditorInfo.IME_ACTION_DONE
            | android.view.inputmethod.EditorInfo.IME_FLAG_NO_EXTRACT_UI);
        searchBox.addView(search, new LayoutParams(0, -2, 1));
        View clear = ui.navigationButton("close", "Clear search", () -> search.setText(""));
        clear.setVisibility(GONE);
        searchBox.addView(clear, params(38, 40));
        LayoutParams searchParams = new LayoutParams(-1, -2);
        searchParams.setMargins(dp(18), 0, dp(18), dp(16));
        addView(searchBox, searchParams);
        android.widget.FrameLayout body = new FrameLayout(owner);
        addView(body, new LayoutParams(-1, 0, 1));
        list = new ListView(owner);
        list.setDivider(null);
        list.setSelector(
            new android.graphics.drawable.ColorDrawable(android.graphics.Color.TRANSPARENT));
        list.setVerticalScrollBarEnabled(false);
        list.setClipToPadding(false);
        list.setPadding(dp(18), 0, dp(18), dp(20));
        list.setAdapter(adapter);
        list.setOnItemClickListener(
            (parent, view, position, id) -> open.accept(shown.get(position).id));
        body.addView(list, new FrameLayout.LayoutParams(-1, -1));
        empty = new LinearLayout(owner);
        empty.setOrientation(VERTICAL);
        empty.setGravity(Gravity.CENTER);
        empty.setPadding(dp(30), dp(30), dp(30), dp(60));
        emptyTitle = label("Loading conversations…", 20, CollieUi.TEXT);
        emptyTitle.setTypeface(Typeface.create("sans-serif-medium", 0));
        emptyTitle.setGravity(Gravity.CENTER);
        empty.addView(emptyTitle);
        emptyBody = label("", 14, CollieUi.MUTED);
        emptyBody.setPadding(0, dp(10), 0, 0);
        emptyBody.setGravity(Gravity.CENTER);
        empty.addView(emptyBody);
        body.addView(empty, new FrameLayout.LayoutParams(-1, -1));
        search.addTextChangedListener(new TextWatcher() {
            public void beforeTextChanged(CharSequence text, int start, int count, int after) {}
            public void onTextChanged(CharSequence text, int start, int before, int count) {
                clear.setVisibility(text.length() == 0 ? GONE : VISIBLE);
                filter();
            }
            public void afterTextChanged(Editable value) {}
        });
        requestFocus();
    }
    private int dp(int n) {
        return (int) (n * getResources().getDisplayMetrics().density + .5f);
    }
    private LayoutParams params(int width, int height) {
        return new LayoutParams(dp(width), dp(height));
    }
    private LinearLayout row() {
        LinearLayout view = new LinearLayout(activity);
        view.setOrientation(HORIZONTAL);
        view.setGravity(Gravity.CENTER_VERTICAL);
        return view;
    }
    private TextView label(String value, int size, int color) {
        TextView view = new TextView(activity);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setIncludeFontPadding(false);
        return view;
    }
    private GradientDrawable background(int color, int radius, int border) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(dp(radius));
        if (border != 0)
            d.setStroke(dp(1), border);
        return d;
    }
    void entries(List<Entry> entries) {
        all.clear();
        all.addAll(entries);
        loading = false;
        filter();
    }
    void failed() {
        loading = false;
        count.setText("Conversations unavailable");
        emptyTitle.setText("Couldn’t load conversations");
        emptyBody.setText("Go back and try again.");
        empty.setVisibility(VISIBLE);
        list.setVisibility(GONE);
    }
    String query() {
        return search.getText().toString();
    }
    void query(String value) {
        search.setText(value);
        search.setSelection(search.length());
    }
    private void filter() {
        String query = search.getText().toString().trim().toLowerCase(Locale.ROOT);
        shown.clear();
        for (Entry entry : all)
            if (query.isEmpty()
                || (entry.title + "\n" + entry.preview).toLowerCase(Locale.ROOT).contains(query))
                shown.add(entry);
        adapter.notifyDataSetChanged();
        count.setText(loading     ? "Loading conversations…"
                : query.isEmpty() ? all.size() + " conversation" + (all.size() == 1 ? "" : "s")
                                  : shown.size() + " of " + all.size() + " conversations");
        empty.setVisibility(shown.isEmpty() ? VISIBLE : GONE);
        list.setVisibility(shown.isEmpty() ? GONE : VISIBLE);
        emptyTitle.setText(loading ? "Loading conversations…"
                : query.isEmpty()  ? "No conversations yet"
                                   : "No conversations found");
        emptyBody.setText(loading ? ""
                : query.isEmpty() ? "Start a new conversation with the + button."
                                  : "Try a different title or message.");
    }
    private final class Adapter extends BaseAdapter {
        final DateFormat date = new SimpleDateFormat("MMM d · HH:mm", Locale.getDefault());
        public int getCount() {
            return shown.size();
        }
        public Object getItem(int position) {
            return shown.get(position);
        }
        public long getItemId(int position) {
            return position;
        }
        public View getView(int position, View recycled, ViewGroup parent) {
            Item item = recycled instanceof Item ? (Item) recycled : new Item();
            Entry entry = shown.get(position);
            item.title.setText(entry.title);
            item.preview.setText(entry.preview);
            item.date.setText(date.format(new Date(entry.updated)));
            item.current.setVisibility(entry.current ? VISIBLE : GONE);
            item.content.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22c5e3ae),
                background(entry.current ? 0xff202c25 : CollieUi.SURFACE, 16,
                    entry.current ? 0xff52664a : CollieUi.BORDER),
                null));
            return item;
        }
    }
    private final class Item extends FrameLayout {
        final LinearLayout content;
        final TextView title, preview, date, current;
        Item() {
            super(activity);
            setPadding(0, 0, 0, dp(10));
            content = new LinearLayout(activity);
            content.setOrientation(VERTICAL);
            content.setDuplicateParentStateEnabled(true);
            content.setPadding(dp(16), dp(16), dp(16), dp(15));
            addView(content, new FrameLayout.LayoutParams(-1, -2));
            LinearLayout headline = row();
            title = label("", 16, CollieUi.TEXT);
            title.setTypeface(Typeface.create("sans-serif-medium", 0));
            title.setMaxLines(1);
            title.setEllipsize(TextUtils.TruncateAt.END);
            headline.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
            current = label("Current", 10, CollieUi.ACCENT);
            current.setPadding(dp(8), dp(4), dp(8), dp(4));
            current.setBackground(background(0xff30402c, 7, 0));
            LinearLayout.LayoutParams badge = new LinearLayout.LayoutParams(-2, -2);
            badge.leftMargin = dp(10);
            headline.addView(current, badge);
            content.addView(headline);
            preview = label("", 13, CollieUi.MUTED);
            preview.setMaxLines(2);
            preview.setEllipsize(TextUtils.TruncateAt.END);
            preview.setLineSpacing(dp(3), 1);
            preview.setPadding(0, dp(9), 0, dp(12));
            content.addView(preview);
            date = label("", 11, CollieUi.MUTED);
            content.addView(date);
        }
    }
}
