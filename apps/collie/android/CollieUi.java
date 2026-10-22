package org.flexscript.collie;

import android.app.Activity;
import android.app.Dialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.Build;
import android.text.Editable;
import android.text.TextWatcher;
import android.text.method.LinkMovementMethod;
import android.view.*;
import android.view.inputmethod.EditorInfo;
import android.widget.*;
import java.util.Locale;
import org.json.JSONObject;
import org.json.JSONArray;

/** Native phone presentation. No framework dependency or model/runtime logic. */
final class CollieUi {
    static final int BG = 0xff10151a, SURFACE = 0xff191f25, SURFACE_HIGH = 0xff232c33;
    static final int TEXT = 0xffedf2ed, MUTED = 0xff8e9d9f, ACCENT = 0xffc5e3ae,
                     BORDER = 0xff2c353b;
    static final int ERROR = 0xfff1aaa6, USER = 0xff25332b;
    private final Activity activity;
    final LinearLayout page, transcript;
    final ScrollView scroll;
    final EditText prompt;
    final TextView status;
    private final TextView context, modelLabel;
    private final Meter meter;
    private final IconButton send, jump, attach;
    private final HorizontalScrollView attachmentScroll;
    private final LinearLayout attachmentRow;
    private int attachmentCount;
    private final View stateDot;
    private final LinearLayout welcome;
    private final boolean authenticated;
    private boolean busy, followTail = true, scrollPending;
    private ExecutionCard lastExecution;
    private java.io.File workspace;
    void workspace(java.io.File value) { workspace = value; }
    private View streamRoot;

    CollieUi(Activity owner, Runnable submit, Runnable newChat, Runnable conversations,
        Runnable menu, Runnable attachFile, boolean connected) {
        activity = owner;
        authenticated = connected;
        page = column();
        page.setBackgroundColor(BG);
        page.setFocusableInTouchMode(true);
        owner.getWindow().setStatusBarColor(BG);
        owner.getWindow().setNavigationBarColor(BG);
        owner.getWindow().getDecorView().setSystemUiVisibility(0);
        if (Build.VERSION.SDK_INT >= 29)
            owner.getWindow().setNavigationBarContrastEnforced(false);
        if (Build.VERSION.SDK_INT >= 30)
            page.setOnApplyWindowInsetsListener((view, insets) -> {
                Insets bars = insets.getInsets(WindowInsets.Type.systemBars());
                view.setPadding(bars.left, bars.top, bars.right,
                    Math.max(bars.bottom, insets.getInsets(WindowInsets.Type.ime()).bottom));
                toBottom(false);
                return insets;
            });
        else
            page.setOnApplyWindowInsetsListener((view, insets) -> {
                view.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(),
                    insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
                return insets;
            });
        LinearLayout header = row();
        header.setPadding(dp(20), dp(14), dp(14), dp(12));
        Mark avatar = new Mark(owner);
        header.addView(avatar, lp(42, 42));
        LinearLayout identity = column();
        identity.setPadding(dp(12), 0, 0, 0);
        TextView title = label("Collie", 23, TEXT);
        title.setTypeface(Typeface.create("sans-serif-medium", 0));
        identity.addView(title);
        modelLabel = label("gpt-6.1-sol", 12, MUTED);
        identity.addView(modelLabel);
        header.addView(identity, new LinearLayout.LayoutParams(0, -2, 1));
        header.addView(
            iconButton("conversations", "Conversations", conversations, false), lp(44, 44));
        header.addView(iconButton("plus", "New conversation", newChat, false), lp(44, 44));
        header.addView(iconButton("more", "Menu", menu, false), lp(44, 44));
        page.addView(header);
        LinearLayout contextRow = row();
        contextRow.setPadding(dp(22), dp(2), dp(22), dp(10));
        stateDot = new View(owner);
        stateDot.setBackground(shape(ACCENT, 4, 0));
        contextRow.addView(stateDot, lp(5, 5));
        status = label("Ready", 12, MUTED);
        status.setPadding(dp(7), 0, 0, 0);
        contextRow.addView(status, new LinearLayout.LayoutParams(0, -2, 1));
        context = label("Context —", 12, MUTED);
        contextRow.addView(context);
        page.addView(contextRow);
        meter = new Meter(owner);
        page.addView(meter, new LinearLayout.LayoutParams(-1, dp(2)));
        FrameLayout conversation = new FrameLayout(owner);
        scroll = new ScrollView(owner);
        scroll.setFillViewport(true);
        scroll.setClipToPadding(false);
        scroll.setVerticalScrollBarEnabled(false);
        transcript = column();
        transcript.setPadding(dp(18), dp(18), dp(18), dp(16));
        scroll.addView(transcript, new ScrollView.LayoutParams(-1, -2));
        conversation.addView(scroll, new FrameLayout.LayoutParams(-1, -1));
        jump = iconButton("down", "Jump to latest message", () -> toBottom(true), true);
        jump.setVisibility(View.GONE);
        FrameLayout.LayoutParams j =
            new FrameLayout.LayoutParams(dp(42), dp(42), Gravity.BOTTOM | Gravity.RIGHT);
        j.setMargins(0, 0, dp(22), dp(12));
        conversation.addView(jump, j);
        scroll.setOnScrollChangeListener((View view, int x, int y, int oldX, int oldY) -> {
            followTail = scroll.getChildAt(0).getHeight() - (y + scroll.getHeight()) < dp(90);
            jump.setVisibility(followTail ? View.GONE : View.VISIBLE);
        });
        page.addView(conversation, new LinearLayout.LayoutParams(-1, 0, 1));
        LinearLayout footer = column();
        footer.setPadding(dp(16), dp(8), dp(16), dp(12));
        attachmentScroll = new HorizontalScrollView(owner);
        attachmentScroll.setHorizontalScrollBarEnabled(false);
        attachmentRow = row();
        attachmentScroll.addView(attachmentRow);
        attachmentScroll.setVisibility(View.GONE);
        footer.addView(attachmentScroll);
        LinearLayout composer = row();
        composer.setPadding(dp(8), dp(5), dp(6), dp(5));
        composer.setBackground(shape(SURFACE, 26, BORDER));
        attach = iconButton("plus", "Attach file", attachFile, false);
        composer.addView(attach, lp(44, 44));
        prompt = new EditText(owner);
        prompt.setTextColor(TEXT);
        prompt.setHintTextColor(MUTED);
        prompt.setTextSize(16);
        prompt.setTypeface(Typeface.create("sans-serif", 0));
        prompt.setHint("Message Collie…");
        prompt.setContentDescription("Message Collie");
        prompt.setMaxLines(5);
        prompt.setMinLines(1);
        prompt.setPadding(dp(10), dp(9), dp(8), dp(9));
        prompt.setBackgroundColor(Color.TRANSPARENT);
        prompt.setInputType(android.text.InputType.TYPE_CLASS_TEXT
            | android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            | android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        prompt.setImeOptions(EditorInfo.IME_ACTION_SEND | EditorInfo.IME_FLAG_NO_EXTRACT_UI);
        prompt.setOnEditorActionListener((v, action, event) -> {
            if (action == EditorInfo.IME_ACTION_SEND) {
                submit.run();
                return true;
            }
            return false;
        });
        prompt.setOnFocusChangeListener(
            (v, focused)
                -> composer.setBackground(shape(SURFACE, 26, focused ? 0xff63775b : BORDER)));
        composer.addView(prompt, new LinearLayout.LayoutParams(0, -2, 1));
        send = iconButton("send", "Send message", submit, true);
        composer.addView(send, lp(42, 42));
        prompt.addTextChangedListener(new TextWatcher() {
            public void beforeTextChanged(CharSequence s, int st, int c, int a) {}
            public void onTextChanged(CharSequence s, int st, int before, int count) {
                updateSend();
            }
            public void afterTextChanged(Editable e) {}
        });
        footer.addView(composer);
        page.addView(footer);
        updateSend();
        welcome = welcome(menu);
        clear();
        page.requestFocus();
    }
    private int dp(int n) {
        return (int) (n * activity.getResources().getDisplayMetrics().density + .5f);
    }
    private LinearLayout column() {
        LinearLayout l = new LinearLayout(activity);
        l.setOrientation(LinearLayout.VERTICAL);
        return l;
    }
    private LinearLayout row() {
        LinearLayout l = new LinearLayout(activity);
        l.setOrientation(LinearLayout.HORIZONTAL);
        l.setGravity(Gravity.CENTER_VERTICAL);
        return l;
    }
    private LinearLayout.LayoutParams lp(int w, int h) {
        return new LinearLayout.LayoutParams(w < 0 ? w : dp(w), h < 0 ? h : dp(h));
    }
    private TextView label(String s, int size, int color) {
        TextView t = new TextView(activity);
        t.setText(s);
        t.setTextSize(size);
        t.setTextColor(color);
        t.setFontFeatureSettings("kern");
        t.setIncludeFontPadding(false);
        return t;
    }
    private TextView body(String s, int color) {
        TextView t = label(s, 16, color);
        t.setTextIsSelectable(true);
        t.setLineSpacing(dp(5), 1);
        t.setTextColor(color);
        t.setLinkTextColor(ACCENT);
        return t;
    }
    private GradientDrawable shape(int color, int radius, int stroke) {
        GradientDrawable d = new GradientDrawable();
        d.setColor(color);
        d.setCornerRadius(dp(radius));
        if (stroke != 0)
            d.setStroke(dp(1), stroke);
        return d;
    }
    private void clickable(View view, int color, int radius) {
        view.setBackground(new RippleDrawable(ColorStateList.valueOf(0x22c5e3ae),
            shape(color, radius, color == Color.TRANSPARENT ? 0 : BORDER), null));
    }
    View navigationButton(String name, String description, Runnable action) {
        return iconButton(name, description, action, false);
    }
    private IconButton iconButton(
        String icon, String description, Runnable action, boolean filled) {
        IconButton b = new IconButton(activity, icon);
        b.setContentDescription(description);
        clickable(b, filled ? SURFACE_HIGH : Color.TRANSPARENT, 24);
        b.setOnClickListener(v -> action.run());
        return b;
    }
    private void spaced(View child, int top, int bottom) {
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
        p.topMargin = dp(top);
        p.bottomMargin = dp(bottom);
        transcript.addView(child, p);
    }
    private LinearLayout welcome(Runnable menu) {
        LinearLayout l = column();
        l.setGravity(Gravity.CENTER);
        l.setPadding(dp(12), dp(26), dp(12), dp(32));
        Mark mark = new Mark(activity);
        l.addView(mark, lp(62, 62));
        TextView eyebrow = label("A LITTLE HELP. A LOT POSSIBLE.", 10, MUTED);
        eyebrow.setLetterSpacing(.14f);
        eyebrow.setPadding(0, dp(22), 0, dp(14));
        l.addView(eyebrow);
        TextView title = label("What are we\nworking on?", 29, TEXT);
        title.setGravity(Gravity.CENTER);
        title.setTypeface(Typeface.create("sans-serif-medium", 0));
        title.setLineSpacing(dp(3), 1);
        l.addView(title);
        TextView subtitle = label("A thought partner with a workspace of its own.", 14, MUTED);
        subtitle.setGravity(Gravity.CENTER);
        subtitle.setPadding(0, dp(13), 0, dp(30));
        l.addView(subtitle);
        suggestion(l, "Make a plan", "Turn a big idea into a first step",
            "Help me break down a project into clear next steps.");
        suggestion(l, "Explore my workspace", "See what’s here and pick up a thread",
            "Show me what’s in my workspace.");
        if (!authenticated) {
            TextView connect = label("Connect ChatGPT to get started  →", 13, ACCENT);
            connect.setPadding(dp(14), dp(18), dp(14), dp(10));
            connect.setOnClickListener(v -> menu.run());
            connect.setContentDescription("Connect ChatGPT");
            l.addView(connect);
        }
        return l;
    }
    private void suggestion(LinearLayout parent, String title, String subtitle, String value) {
        LinearLayout item = row();
        item.setPadding(dp(16), dp(14), dp(12), dp(14));
        clickable(item, SURFACE, 16);
        LinearLayout labels = column();
        TextView heading = label(title, 14, TEXT);
        heading.setTypeface(Typeface.create("sans-serif-medium", 0));
        labels.addView(heading);
        TextView desc = label(subtitle, 12, MUTED);
        desc.setPadding(0, dp(5), 0, 0);
        labels.addView(desc);
        item.addView(labels, new LinearLayout.LayoutParams(0, -2, 1));
        IconButton arrow = new IconButton(activity, "right");
        arrow.setClickable(false);
        arrow.setFocusable(false);
        item.addView(arrow, lp(22, 22));
        item.setOnClickListener(v -> {
            prompt.setText(value);
            prompt.setSelection(value.length());
            prompt.requestFocus();
            ((android.view.inputmethod.InputMethodManager) activity.getSystemService(
                 Context.INPUT_METHOD_SERVICE))
                .showSoftInput(prompt, 0);
        });
        LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
        p.topMargin = dp(8);
        parent.addView(item, p);
    }
    void clear() {
        transcript.removeAllViews();
        lastExecution = null;
        streamRoot = null;
        followTail = true;
        transcript.setGravity(Gravity.CENTER_VERTICAL);
        transcript.addView(welcome, new LinearLayout.LayoutParams(-1, -2));
    }
    private void dismissWelcome() {
        if (welcome.getParent() != null) {
            transcript.removeView(welcome);
            transcript.setGravity(Gravity.TOP);
        }
    }
    void toBottom(boolean force) {
        if (force)
            followTail = true;
        if (!followTail || scrollPending)
            return;
        scrollPending = true;
        scroll.postOnAnimation(() -> {
            scrollPending = false;
            scroll.scrollTo(0, Math.max(0, transcript.getHeight() - scroll.getHeight()));
        });
    }
    void setWorking(boolean value) {
        busy = value;
        stateDot.setBackground(shape(value ? 0xffe2c49c : ACCENT, 4, 0));
        if (!value) {
            status.setText("Ready");
            removeStream();
        }
        updateSend();
    }
    private void updateSend() {
        boolean enabled = busy || attachmentCount > 0 || !prompt.getText().toString().trim().isEmpty();
        attach.setEnabled(!busy);
        attach.setAlpha(busy ? .35f : 1f);
        send.setEnabled(enabled);
        send.setAlpha(enabled ? 1f : .35f);
        send.icon = busy ? "stop" : "send";
        send.ink = BG;
        send.setBackground(shape(busy ? ERROR : ACCENT, 22, 0));
        send.setContentDescription(busy ? "Stop response" : "Send message");
        send.invalidate();
    }
    void attachments(JSONArray files, java.util.function.IntConsumer remove) {
        attachmentRow.removeAllViews();
        attachmentCount = files.length();
        attachmentScroll.setVisibility(attachmentCount == 0 ? View.GONE : View.VISIBLE);
        for (int i = 0; i < files.length(); i++) {
            final int index = i;
            JSONObject file = files.optJSONObject(i);
            if (file != null)
                AttachmentViews.attachment(activity, attachmentRow, file, workspace,
                    () -> { if (!busy) remove.accept(index); });
        }
        updateSend();
    }
    void context(String model, long used, long total, boolean estimated) {
        modelLabel.setText(model);
        context.setText(
            "Context " + (estimated ? "~" : "") + compact(used) + " / " + compact(total));
        context.setContentDescription(
            "Context " + (estimated ? "approximately " : "") + used + " of " + total + " tokens");
        meter.fraction = total > 0 ? Math.min(1f, (float) used / total) : 0;
        meter.invalidate();
    }
    void contextUnavailable() {
        context.setText("Context unavailable");
    }
    private String compact(long value) {
        if (value < 1000)
            return String.valueOf(value);
        if (value < 10000)
            return String.format(Locale.US, "%.1fk", value / 1000.0);
        return String.format(Locale.US, "%.0fk", value / 1000.0);
    }
    void render(JSONObject card) {
        String kind = card.optString("kind"), value = card.optString("text");
        if (kind.equals("info") && value.startsWith("App-private workspace ready."))
            return;
        dismissWelcome();
        if (kind.equals("source")) {
            lastExecution = new ExecutionCard(value);
            spaced(lastExecution, 5, 16);
        } else if (kind.equals("result")) {
            if (lastExecution == null) {
                lastExecution = new ExecutionCard("");
                spaced(lastExecution, 5, 16);
            }
            lastExecution.result(card);
            lastExecution = null;
        } else if (kind.equals("user")) {
            lastExecution = null;
            LinearLayout alignment = row();
            alignment.setGravity(Gravity.RIGHT);
            LinearLayout bubble = column();
            bubble.setPadding(dp(17), dp(14), dp(17), dp(14));
            bubble.setBackground(shape(USER, 20, 0));
            TextView content = body(value, TEXT);
            if (!value.isEmpty()) bubble.addView(content);
            JSONArray files = card.optJSONArray("attachments");
            if (files != null) for (int i = 0; i < files.length(); i++) {
                JSONObject file = files.optJSONObject(i);
                if (file != null) AttachmentViews.attachment(activity, bubble, file, workspace, null);
            }
            // Give text its final width before measuring its height alongside attachment tiles.
            LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(
                files != null && files.length() > 0 ? -1 : -2, -2);
            p.leftMargin = dp(30);
            alignment.addView(bubble, p);
            spaced(alignment, 12, 24);
        } else if (kind.equals("assistant")) {
            lastExecution = null;
            View box = assistant(value);
            spaced(box, 3, 22);
        } else if (kind.equals("error")) {
            lastExecution = null;
            LinearLayout box = column();
            box.setPadding(dp(16), dp(14), dp(16), dp(14));
            box.setBackground(shape(0xff2b2023, 16, 0xff54353a));
            TextView title = label("Something needs attention", 13, ERROR);
            title.setTypeface(null, Typeface.BOLD);
            box.addView(title);
            TextView desc = body(value, 0xffe9c5c2);
            desc.setTextSize(14);
            desc.setPadding(0, dp(8), 0, 0);
            box.addView(desc);
            spaced(box, 4, 16);
        } else {
            TextView note = label(value, 12, MUTED);
            note.setGravity(Gravity.CENTER);
            note.setPadding(dp(14), dp(12), dp(14), dp(12));
            spaced(note, 0, 10);
        }
        toBottom(false);
    }
    private LinearLayout assistant(String content) {
        LinearLayout box = column();
        LinearLayout heading = row();
        Mark mini = new Mark(activity);
        heading.addView(mini, lp(22, 22));
        TextView name = label("Collie", 13, ACCENT);
        name.setTypeface(Typeface.create("sans-serif-medium", 0));
        name.setPadding(dp(8), 0, 0, 0);
        heading.addView(name, new LinearLayout.LayoutParams(0, -2, 1));
        if (!content.isEmpty())
            heading.addView(
                iconButton("copy", "Copy reply", () -> copy("Collie reply", content), false),
                lp(30, 30));
        box.addView(heading);
        TextView message = body("", TEXT);
        message.setText(MessageStyle.markdown(content));
        message.setMovementMethod(LinkMovementMethod.getInstance());
        message.setPadding(0, dp(10), 0, 0);
        box.addView(message);
        message.setTag(box);
        return box;
    }
    TextView beginStream() {
        dismissWelcome();
        removeStream();
        LinearLayout root = assistant("");
        streamRoot = root;
        root.setVisibility(View.GONE);
        spaced(root, 3, 22);
        return (TextView) root.getChildAt(1);
    }
    void stream(TextView view, String content) {
        View root = (View) view.getTag();
        root.setVisibility(View.VISIBLE);
        view.setText(MessageStyle.markdown(content));
        toBottom(false);
    }
    void removeStream() {
        if (streamRoot != null) {
            transcript.removeView(streamRoot);
            streamRoot = null;
        }
    }
    private void copy(String label, String value) {
        ((ClipboardManager) activity.getSystemService(Context.CLIPBOARD_SERVICE))
            .setPrimaryClip(ClipData.newPlainText(label, value));
        if (Build.VERSION.SDK_INT < 33)
            Toast.makeText(activity, "Copied", Toast.LENGTH_SHORT).show();
    }

    private final class ExecutionCard extends LinearLayout {
        final String source;
        final LinearLayout header, details, results;
        final TextView state, action;
        final IconButton chevron;
        boolean expanded, resultExpanded;
        ExecutionCard(String text) {
            super(activity);
            source = text;
            setOrientation(VERTICAL);
            setBackground(shape(SURFACE, 16, BORDER));
            setClipToOutline(true);
            header = row();
            header.setPadding(dp(14), dp(13), dp(10), dp(13));
            header.setMinimumHeight(dp(60));
            header.setContentDescription("Show program");
            header.setFocusable(true);
            clickable(header, Color.TRANSPARENT, 16);
            TextView symbol = label("{ }", 17, ACCENT);
            symbol.setTypeface(Typeface.MONOSPACE);
            symbol.setGravity(Gravity.CENTER);
            symbol.setBackground(shape(SURFACE_HIGH, 10, 0));
            header.addView(symbol, lp(34, 34));
            LinearLayout caption = column();
            caption.setPadding(dp(11), 0, 0, 0);
            TextView name = label("Flexscript", 14, TEXT);
            name.setTypeface(Typeface.create("sans-serif-medium", 0));
            caption.addView(name);
            action = label("Show program", 11, MUTED);
            action.setPadding(0, dp(5), 0, 0);
            caption.addView(action);
            header.addView(caption, new LinearLayout.LayoutParams(0, -2, 1));
            state = label("Program", 10, MUTED);
            state.setPadding(dp(8), dp(5), dp(8), dp(5));
            state.setBackground(shape(SURFACE_HIGH, 8, 0));
            header.addView(state);
            chevron = new IconButton(activity, "down");
            chevron.setClickable(false);
            chevron.setFocusable(false);
            header.addView(chevron, lp(26, 26));
            addView(header);
            details = column();
            details.setVisibility(View.GONE);
            LinearLayout tools = row();
            tools.setPadding(dp(14), 0, dp(9), dp(6));
            TextView lines =
                label((source.isEmpty() ? 0 : source.split("\n", -1).length) + " lines", 11, MUTED);
            tools.addView(lines, new LinearLayout.LayoutParams(0, -2, 1));
            tools.addView(
                iconButton("copy", "Copy program", () -> copy("Flexscript", source), false),
                lp(30, 30));
            details.addView(tools);
            HorizontalScrollView codeScroll = new HorizontalScrollView(activity);
            codeScroll.setFillViewport(true);
            codeScroll.setBackgroundColor(0xff0d1217);
            codeScroll.setHorizontalScrollBarEnabled(true);
            LinearLayout codeRow = row();
            codeRow.setGravity(Gravity.TOP);
            codeRow.setPadding(dp(13), dp(14), dp(16), dp(14));
            StringBuilder nums = new StringBuilder();
            int count = source.split("\n", -1).length;
            for (int i = 1; i <= count; i++) {
                if (i > 1)
                    nums.append('\n');
                nums.append(i);
            }
            TextView numbers = label(nums.toString(), 12, 0xff59656e);
            numbers.setTypeface(Typeface.MONOSPACE);
            numbers.setGravity(Gravity.RIGHT);
            numbers.setLineSpacing(dp(4), 1);
            numbers.setPadding(0, 0, dp(14), 0);
            codeRow.addView(numbers);
            TextView code = label("", 12, 0xffd8e2e7);
            code.setText(MessageStyle.code(source));
            code.setTypeface(Typeface.MONOSPACE);
            code.setTextIsSelectable(true);
            code.setLineSpacing(dp(4), 1);
            code.setHorizontallyScrolling(true);
            codeRow.addView(code);
            codeScroll.addView(codeRow, new HorizontalScrollView.LayoutParams(-2, -2));
            details.addView(codeScroll);
            addView(details);
            results = column();
            addView(results);
            header.setOnClickListener(v -> {
                expanded = !expanded;
                details.setVisibility(expanded ? View.VISIBLE : View.GONE);
                action.setText(expanded ? "Hide program" : "Show program");
                header.setContentDescription(expanded ? "Hide program" : "Show program");
                chevron.icon = expanded ? "up" : "down";
                chevron.invalidate();
            });
        }
        void result(JSONObject card) {
            results.removeAllViews();
            String raw = card.optString("text");
            JSONObject observation = card.optJSONObject("observation");
            boolean failed;
            String output, error = "", meta;
            if (observation != null) {
                String status = observation.optString("state");
                int exit = observation.optInt("exit_code", -1);
                failed = status.equals("error") || status.equals("rejected");
                output = observation.optString("stdout");
                error = observation.optString("stderr");
                meta = failed ? (status.equals("rejected") ? "Rejected" : "Error")
                              : (exit == 0 ? "Completed" : "Exit " + exit);
                if (observation.optBoolean("output_truncated"))
                    error += (error.isEmpty() ? "" : "\n") + "Output truncated";
            } else {
                int newline = raw.indexOf('\n');
                String first = newline < 0 ? raw : raw.substring(0, newline);
                output = newline < 0 ? "" : raw.substring(newline + 1);
                failed = first.startsWith("error") || first.startsWith("rejected");
                if (failed) {
                    error = output;
                    output = "";
                }
                meta = failed ? "Error" : "Completed";
            }
            state.setText(meta);
            state.setTextColor(failed ? ERROR : ACCENT);
            state.setBackground(shape(failed ? 0xff40292c : 0xff29372b, 8, 0));
            View divider = new View(activity);
            divider.setBackgroundColor(BORDER);
            results.addView(divider, new LinearLayout.LayoutParams(-1, dp(1)));
            LinearLayout resultHeader = row();
            resultHeader.setPadding(dp(15), dp(10), dp(10), dp(10));
            resultHeader.setMinimumHeight(dp(44));
            resultHeader.setFocusable(true);
            clickable(resultHeader, Color.TRANSPARENT, 0);
            TextView resultLabel = label("VM result", 12, MUTED);
            resultHeader.addView(resultLabel, new LinearLayout.LayoutParams(0, -2, 1));
            TextView resultAction = label("", 11, ACCENT);
            resultHeader.addView(resultAction);
            IconButton resultChevron = new IconButton(activity, "down");
            resultChevron.setClickable(false);
            resultChevron.setFocusable(false);
            resultChevron.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
            resultHeader.addView(resultChevron, lp(26, 26));
            results.addView(resultHeader);
            LinearLayout content = column();
            content.setPadding(dp(15), 0, dp(15), dp(14));
            if (output.trim().isEmpty() && error.isEmpty()) {
                TextView empty = label("Finished without output", 12, MUTED);
                empty.setPadding(0, dp(7), 0, 0);
                content.addView(empty);
            } else {
                if (!output.isEmpty())
                    output(content, output, 0xffdce9d7);
                if (!error.isEmpty())
                    output(content, error, ERROR);
            }
            if (observation != null) {
                org.json.JSONArray views=observation.optJSONArray("views");
                if (views != null) for(int i=0;i<views.length();i++) {
                    JSONObject view=views.optJSONObject(i);if(view!=null)AttachmentViews.add(activity,content,view,workspace);
                }
            }
            results.addView(content);
            Runnable updateResult = () -> {
                content.setVisibility(resultExpanded ? View.VISIBLE : View.GONE);
                resultAction.setText(resultExpanded ? "Hide result" : "Show result");
                resultHeader.setContentDescription(resultExpanded ? "Hide VM result" : "Show VM result");
                resultChevron.icon = resultExpanded ? "up" : "down";
                resultChevron.invalidate();
            };
            updateResult.run();
            resultHeader.setOnClickListener(v -> {
                resultExpanded = !resultExpanded;
                updateResult.run();
            });
            toBottom(false);
        }
        private void output(LinearLayout parent, String value, int color) {
            TextView out = body(value.replaceAll("\\n+$", ""), color);
            out.setTypeface(Typeface.MONOSPACE);
            out.setTextSize(13);
            out.setPadding(0, dp(7), 0, 0);
            parent.addView(out);
        }
    }
    void sheet(String title, String subtitle, String[] items, Runnable[] actions) {
        Dialog dialog = new Dialog(activity);
        LinearLayout panel = column();
        panel.setPadding(dp(20), dp(12), dp(20), dp(24));
        panel.setBackground(shape(SURFACE, 24, 0));
        View handle = new View(activity);
        handle.setBackground(shape(0xff4b555d, 3, 0));
        LinearLayout.LayoutParams h = lp(34, 4);
        h.gravity = Gravity.CENTER_HORIZONTAL;
        h.bottomMargin = dp(23);
        panel.addView(handle, h);
        TextView heading = label(title, 22, TEXT);
        heading.setTypeface(Typeface.create("sans-serif-medium", 0));
        panel.addView(heading);
        TextView sub = label(subtitle, 13, MUTED);
        sub.setPadding(0, dp(8), 0, dp(18));
        panel.addView(sub);
        for (int i = 0; i < items.length; i++) {
            final int at = i;
            TextView item = label(items[i], 15, TEXT);
            item.setPadding(dp(12), dp(16), dp(12), dp(16));
            clickable(item, Color.TRANSPARENT, 12);
            item.setOnClickListener(v -> {
                dialog.dismiss();
                actions[at].run();
            });
            panel.addView(item);
        }
        ScrollView wrapper = new ScrollView(activity);
        wrapper.addView(panel);
        dialog.setContentView(wrapper);
        Window w = dialog.getWindow();
        if (w != null) {
            w.setBackgroundDrawableResource(android.R.color.transparent);
            w.setLayout(-1, -2);
            w.setGravity(Gravity.BOTTOM);
            w.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
            WindowManager.LayoutParams a = w.getAttributes();
            a.dimAmount = .55f;
            w.setAttributes(a);
        }
        dialog.show();
        if (w != null)
            w.setLayout(-1, -2);
    }
    private final class IconButton extends View {
        String icon;
        int ink = MUTED;
        final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        IconButton(Context context, String name) {
            super(context);
            icon = name;
            setClickable(true);
            setFocusable(true);
        }
        @Override
        public CharSequence getAccessibilityClassName() {
            return "android.widget.Button";
        }
        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            canvas.save();
            float scale = Math.min(getWidth(), getHeight()) / 44f;
            canvas.translate(getWidth() / 2f, getHeight() / 2f);
            canvas.scale(scale, scale);
            p.setColor(ink);
            p.setStyle(Paint.Style.STROKE);
            p.setStrokeWidth(1.8f);
            p.setStrokeCap(Paint.Cap.ROUND);
            p.setStrokeJoin(Paint.Join.ROUND);
            if (icon.equals("plus")) {
                canvas.drawLine(-7, 0, 7, 0, p);
                canvas.drawLine(0, -7, 0, 7, p);
            } else if (icon.equals("more")) {
                p.setStyle(Paint.Style.FILL);
                for (int x = -6; x <= 6; x += 6) canvas.drawCircle(x, 0, 1.5f, p);
            } else if (icon.equals("stop")) {
                p.setStyle(Paint.Style.FILL);
                canvas.drawRoundRect(-6, -6, 6, 6, 2, 2, p);
            } else if (icon.equals("copy")) {
                canvas.drawRoundRect(-4, -4, 6, 7, 2, 2, p);
                canvas.drawLine(-7, 3, -7, -7, p);
                canvas.drawLine(-7, -7, 2, -7, p);
            } else if (icon.equals("send")) {
                canvas.drawLine(0, 8, 0, -7, p);
                canvas.drawLine(0, -7, -6, -1, p);
                canvas.drawLine(0, -7, 6, -1, p);
            } else if (icon.equals("conversations")) {
                for (int y = -6; y <= 6; y += 6) {
                    canvas.drawLine(-2, y, 7, y, p);
                    canvas.drawCircle(-7, y, .8f, p);
                }
            } else if (icon.equals("back")) {
                canvas.drawLine(7, 0, -7, 0, p);
                canvas.drawLine(-7, 0, -1, -6, p);
                canvas.drawLine(-7, 0, -1, 6, p);
            } else if (icon.equals("search")) {
                canvas.drawCircle(-1, -1, 5, p);
                canvas.drawLine(3, 3, 8, 8, p);
            } else if (icon.equals("close")) {
                canvas.drawLine(-5, -5, 5, 5, p);
                canvas.drawLine(-5, 5, 5, -5, p);
            } else if (icon.equals("right")) {
                canvas.drawLine(-5, -6, 1, 0, p);
                canvas.drawLine(1, 0, -5, 6, p);
            } else {
                int sign = icon.equals("up") ? -1 : 1;
                canvas.drawLine(-5, -2 * sign, 0, 3 * sign, p);
                canvas.drawLine(0, 3 * sign, 5, -2 * sign, p);
            }
            canvas.restore();
        }
    }
    private static final class Mark extends View {
        private final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final android.graphics.drawable.Drawable artwork;
        Mark(Context c) {
            super(c);
            setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
            int id = getResources().getIdentifier("collie_border_collie", "drawable", c.getPackageName());
            artwork = c.getDrawable(id);
            if (artwork instanceof android.graphics.drawable.BitmapDrawable)
                ((android.graphics.drawable.BitmapDrawable) artwork).setFilterBitmap(true);
        }
        @Override
        protected void onDraw(Canvas c) {
            float size = Math.min(getWidth(), getHeight());
            c.save();
            c.scale(size / 48, size / 48);
            p.setColor(USER);
            c.drawRoundRect(0, 0, 48, 48, 15, 15, p);
            artwork.setBounds(5, 5, 43, 43);
            artwork.draw(c);
            c.restore();
        }
    }
    private static final class Meter extends View {
        float fraction;
        private final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        Meter(Context c) {
            super(c);
            setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        }
        @Override
        protected void onDraw(Canvas c) {
            p.setColor(BORDER);
            c.drawRect(0, 0, getWidth(), getHeight(), p);
            p.setColor(fraction > .85f ? 0xffe2c49c : 0xff657c59);
            c.drawRect(0, 0, getWidth() * fraction, getHeight(), p);
        }
    }
}
