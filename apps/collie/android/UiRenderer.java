package org.flexscript.collie;

import android.app.Activity;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.text.method.LinkMovementMethod;
import android.view.inputmethod.EditorInfo;
import java.io.File;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Looper;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.*;
import java.util.*;
import org.json.*;

/** Generic native adapter for Flexscript UI wire ABI1. No Collie screen policy. */
final class UiRenderer extends FrameLayout {
    interface Events { void dispatch(JSONObject event); }
    private static final class Node {
        String key, kind, text = "", action = "";
        long actionId;
        View view;
        JSONObject props = new JSONObject();
        boolean changing, hidden;
        String renderedText = null, inputOptions = null;
        Node(String key, String kind, View view) {
            this.key = key; this.kind = kind; this.view = view;
        }
    }
    private File workspace;
    void workspace(File value) { workspace=value; }
    View widget(String key) { Node n=nodes.get(key); return n==null?null:n.view; }
    private final Activity activity;
    private final Events events;
    private final Map<String, Node> nodes = new HashMap<>();

    UiRenderer(Activity owner, Events callback) { super(owner); activity = owner; events = callback; }
    private int dp(float value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    private static int number(JSONObject props, String key, int fallback) {
        return props.has(key) ? Integer.parseInt(props.optString(key)) : fallback;
    }
    private static int color(JSONObject props, String key, int fallback) {
        return props.has(key) ? Color.parseColor(props.optString(key)) : fallback;
    }
    private int themeColor(int attribute) {
        android.util.TypedValue value=new android.util.TypedValue();
        return activity.getTheme().resolveAttribute(attribute,value,true) ? value.data : Color.GRAY;
    }
    private ViewGroup group(String key) {
        if (key.equals("mount")) return this;
        Node node = need(key);
        if (!(node.view instanceof ViewGroup)) throw new IllegalArgumentException("UI parent is a leaf: " + key);
        return (ViewGroup)node.view;
    }
    private Node need(String key) {
        Node node = nodes.get(key);
        if (node == null) throw new IllegalArgumentException("Missing UI node: " + key);
        return node;
    }
    private void event(Node node, String type, Object value) {
        if (node.changing || (node.action.isEmpty() && !type.equals("link"))) return;
        try {
            events.dispatch(new JSONObject().put("key", node.key).put("type", type)
                            .put("action", node.action).put("action_id", node.actionId)
                            .put("value", value));
        } catch (JSONException error) { throw new IllegalArgumentException(error); }
    }
    private Bitmap bitmap(String source) {
        if (!source.startsWith("preview:")) return null;
        try { return BitmapFactory.decodeFile(VmViews.image(workspace,source.substring(8)).getAbsolutePath()); }
        catch (Exception error) { return null; }
    }
    void focus(String key) {
        View view=widget(key);
        if (view==null) return;
        view.requestFocus();
        if (view instanceof EditText) ((android.view.inputmethod.InputMethodManager)activity.getSystemService(Activity.INPUT_METHOD_SERVICE)).showSoftInput(view,0);
    }
    void bottom(String key, boolean force) {
        View view=widget(key);
        if (view instanceof ScrollView) {
            ScrollView scroll=(ScrollView)view;
            if (force || scroll.getChildCount()==0 || scroll.getChildAt(0).getHeight()-(scroll.getScrollY()+scroll.getHeight())<dp(100))
                scroll.postOnAnimation(() -> tail(scroll));
        }
    }
    private void tail(ScrollView scroll) {
        // fullScroll also moves keyboard focus into the transcript. Follow the
        // tail without stealing an editor's focus or interrupting its IME.
        if (scroll.getChildCount()>0)
            scroll.scrollTo(0,Math.max(0,scroll.getChildAt(0).getBottom()+scroll.getPaddingBottom()-scroll.getHeight()));
    }
    private Node create(String key, String kind, JSONObject props) {
        View view;
        switch (kind) {
        case "column": case "row":
            LinearLayout layout = new LinearLayout(activity);
            layout.setOrientation(kind.equals("row") ? LinearLayout.HORIZONTAL : LinearLayout.VERTICAL);
            layout.setGravity(kind.equals("row") ? Gravity.CENTER_VERTICAL : Gravity.TOP);
            view = layout; break;
        case "stack": view = new FrameLayout(activity); break;
        case "hscroll": view = new HorizontalScrollView(activity); break;
        case "progress": view = new ProgressBar(activity,null,android.R.attr.progressBarStyleHorizontal); ((ProgressBar)view).setMax(1000); break;
        case "scroll":
            ScrollView scroll = new ScrollView(activity); scroll.setFillViewport(true); view = scroll; break;
        case "text": view = new TextView(activity); break;
        case "button": view = new Button(activity); break;
        case "input": view = new EditText(activity); break;
        case "check": Switch toggle = new Switch(activity); toggle.setShowText(false); view = toggle; break;
        case "image":
            Bitmap bitmap = number(props,"zoom",0)>0 ? bitmap(props.optString("source")) : null;
            view = bitmap == null ? new ImageView(activity) : new UiZoomImage(activity, bitmap);
            break;
        default: throw new IllegalArgumentException("Unsupported UI widget: " + kind);
        }
        Node node = new Node(key, kind, view);
        view.setTag(key); nodes.put(key, node);
        if (view instanceof Switch) {
            ((Switch)view).setOnCheckedChangeListener((v, checked) -> event(node, "change", checked));
        } else if (view instanceof EditText) {
            ((EditText)view).setOnEditorActionListener((v, action, keyEvent) -> {
                if (action == EditorInfo.IME_ACTION_SEND) { event(node,"submit",v.getText().toString()); return true; }
                return false;
            });
            ((EditText)view).addTextChangedListener(new TextWatcher() {
                public void beforeTextChanged(CharSequence s, int start, int count, int after) {}
                public void onTextChanged(CharSequence s, int start, int before, int count) { event(node, "change", s.toString()); }
                public void afterTextChanged(Editable s) {}
            });
        } else {
            view.setOnClickListener(v -> event(node, "click", JSONObject.NULL));
        }
        return node;
    }
    private void properties(Node node, JSONObject props) {
        JSONObject prior = node.props;
        View view = node.view;
        node.props = props;
        node.changing = true;
        try {
            int padding = number(props, "padding", 0), x = number(props, "padding_x", padding), y = number(props, "padding_y", padding);
            view.setPadding(dp(x), dp(y), dp(x), dp(y));
            view.setMinimumHeight(dp(number(props, "min_height", 0)));
            view.setVisibility(node.hidden ? View.GONE : View.VISIBLE);
            view.setEnabled(!props.optString("enabled").equals("false"));
            view.setAlpha(number(props,"alpha",100)/100f);
            GradientDrawable shape = new GradientDrawable();
            shape.setColor(color(props, "background", Color.TRANSPARENT));
            shape.setCornerRadius(dp(number(props, "radius", 0)));
            shape.setStroke(dp(number(props, "border_width", 0)), color(props, "border_color", Color.TRANSPARENT));
            view.setBackground(shape);
            if (view instanceof TextView) {
                TextView text = (TextView)view;
                text.setTextColor(color(props, "color", Color.BLACK));
                text.setTextSize(number(props, "size", 14));
                String font = props.optString("font");
                text.setTypeface(font.equals("monospace") ? Typeface.MONOSPACE : Typeface.create(font.equals("medium") ? "sans-serif-medium" : "sans-serif", 0));
                text.setLineSpacing(dp(number(props,"line_height",0)),1);
                text.setTextIsSelectable(number(props,"selectable",0)>0);
                if (view instanceof Button) ((Button)view).setAllCaps(false);
                if (view instanceof EditText) {
                    EditText input=(EditText)view;
                    input.setHint(node.text);
                    input.setHintTextColor(color(props,"hint_color",Color.GRAY));
                    String caps=props.optString("autocapitalize","none");
                    String options=props.optString("single_line")+":"+props.optString("ime")+":"+caps;
                    if (!options.equals(node.inputOptions)) {
                        input.setSingleLine(number(props,"single_line",0)>0);
                        int capital=caps.equals("sentences")?android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES:caps.equals("words")?android.text.InputType.TYPE_TEXT_FLAG_CAP_WORDS:caps.equals("characters")?android.text.InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS:0;
                        input.setInputType(android.text.InputType.TYPE_CLASS_TEXT | capital |
                                           (number(props,"single_line",0)>0?0:android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE));
                        input.setImeOptions((props.optString("ime").equals("send")?EditorInfo.IME_ACTION_SEND:EditorInfo.IME_ACTION_DONE)|EditorInfo.IME_FLAG_NO_EXTRACT_UI);
                        node.inputOptions=options;
                    }
                    input.setMaxLines(number(props,"max_lines",5));
                    input.setMinLines(number(props,"min_lines",1));
                    String value=props.optString("value", "");
                    if (!Objects.equals(prior.opt("value"), props.opt("value")) && !input.getText().toString().equals(value)) input.setText(value);
                } else if (!(view instanceof Switch)) {
                    String content = props.has("timestamp") ? new java.text.SimpleDateFormat("MMM d · HH:mm",java.util.Locale.getDefault()).format(new java.util.Date(Long.parseLong(props.optString("timestamp")))) : node.text;
                    String signature = content + "\u0000" + props.optString("runs");
                    if (!signature.equals(node.renderedText)) {
                        try { text.setText(props.has("runs") ? UiRichText.spans(props.getString("runs"),href -> event(node,"link",href)) : content); }
                        catch (JSONException error) { throw new IllegalArgumentException(error); }
                        node.renderedText=signature;
                    }
                    text.setMaxLines(number(props,"max_lines",Integer.MAX_VALUE));
                    if (props.has("runs")) text.setMovementMethod(LinkMovementMethod.getInstance());
                }
            }
            String description = props.optString("description", node.kind.equals("check") ? node.text : "");
            view.setContentDescription(description.isEmpty() ? null : description);
            if (view instanceof Switch) {
                int ink = color(props, "color", themeColor(android.R.attr.colorAccent));
                int normal=themeColor(android.R.attr.colorControlNormal);
                ((Switch)view).setThumbTintList(new ColorStateList(new int[][]{{android.R.attr.state_checked}, {}}, new int[]{ink, normal}));
                ((Switch)view).setTrackTintList(new ColorStateList(new int[][]{{android.R.attr.state_checked}, {}}, new int[]{(ink&0x00ffffff)|0x66000000, (normal&0x00ffffff)|0x33000000}));
            }
            if (view instanceof ImageView && !Objects.equals(prior.opt("source"), props.opt("source"))) {
                String source = props.optString("source");
                ImageView image=(ImageView)view;
                if (!(image instanceof UiZoomImage)) {
                    if (source.startsWith("resource:")) {
                        String[] resource=source.substring(9).split("/",2);
                        image.setImageResource(resource.length==2?getResources().getIdentifier(resource[1],resource[0],activity.getPackageName()):0);
                    } else if (source.startsWith("preview:")) image.setImageBitmap(bitmap(source));
                    else image.setImageURI(source.isEmpty()?null:Uri.parse(source));
                    image.setAdjustViewBounds(true);
                }
            }
            if (view instanceof ProgressBar) {
                ((ProgressBar)view).setProgress(number(props,"progress",0));
                ((ProgressBar)view).setProgressTintList(ColorStateList.valueOf(color(props,"color",Color.GRAY)));
            }
            int gravity = Gravity.START;
            String align = props.optString("align");
            if (align.equals("center")) gravity = Gravity.CENTER;
            else if (align.equals("end")) gravity = Gravity.END;
            if (view instanceof TextView) ((TextView)view).setGravity(gravity | Gravity.CENTER_VERTICAL);
            if (view instanceof LinearLayout && props.has("align")) ((LinearLayout)view).setGravity(gravity);
            // TextViews without actions should not announce themselves as buttons.
            if (!(view instanceof Switch) && !(view instanceof EditText)) view.setClickable(!node.action.isEmpty());
            if (!(view instanceof TextView)) view.setFocusable(!node.action.isEmpty());
        } finally { node.changing = false; }
        relayout(node);
        if (view instanceof ViewGroup) layoutChildren((ViewGroup)view);
    }
    private int dimension(JSONObject props, String name, int fallback) {
        int value = number(props, name, fallback); return value < 0 ? value : dp(value);
    }
    private void relayout(Node node) {
        View view = node.view;
        if (!(view.getParent() instanceof ViewGroup)) return;
        ViewGroup parent = (ViewGroup)view.getParent();
        boolean row = parent instanceof LinearLayout && ((LinearLayout)parent).getOrientation() == LinearLayout.HORIZONTAL;
        int weight = number(node.props, "weight", 0);
        int width = dimension(node.props, "width", row ? -2 : -1), height = dimension(node.props, "height", -2);
        if (parent instanceof LinearLayout) {
            if (weight > 0) { if (row) width = 0; else height = 0; }
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(width, height, weight);
            Node parentNode = nodes.get(String.valueOf(parent.getTag()));
            int gap = parentNode == null ? 0 : dp(number(parentNode.props, "gap", 0));
            if (parent.indexOfChild(view) > 0) { if (row) lp.leftMargin = gap; else lp.topMargin = gap; }
            view.setLayoutParams(lp);
        } else {
            FrameLayout.LayoutParams lp=new FrameLayout.LayoutParams(width,height);
            String position=node.props.optString("position");
            if (position.equals("bottom")) lp.gravity=Gravity.BOTTOM;
            else if (position.equals("center")) lp.gravity=Gravity.CENTER;
            view.setLayoutParams(lp);
        }
    }
    private void layoutChildren(ViewGroup parent) {
        for (int i = 0; i < parent.getChildCount(); i++) {
            Node child = nodes.get(String.valueOf(parent.getChildAt(i).getTag()));
            if (child != null) relayout(child);
        }
    }
    private void position(Node node, String parentKey, String after) {
        ViewGroup parent = group(parentKey);
        int index = 0;
        if (!after.isEmpty()) {
            View sibling = need(after).view;
            if (sibling.getParent() != parent) throw new IllegalArgumentException("UI sibling has a different parent");
            index = parent.indexOfChild(sibling) + 1;
        }
        View view = node.view;
        ViewGroup current = view.getParent() instanceof ViewGroup ? (ViewGroup)view.getParent() : null;
        if (current == parent && parent.indexOfChild(view) < index) index--;
        if (current == parent && parent.indexOfChild(view) == index) { relayout(node); return; }
        View focus = view.findFocus();
        if (current == parent) {
            // Reorder the child array without detaching a focused editor from
            // its window. removeView/addView clears focus and IME composition.
            ArrayList<View> order = new ArrayList<>();
            for (int i = 0; i < parent.getChildCount(); i++)
                if (parent.getChildAt(i) != view) order.add(parent.getChildAt(i));
            order.add(index, view);
            parent.bringChildToFront(view);
            for (int i = index + 1; i < order.size(); i++) parent.bringChildToFront(order.get(i));
        } else {
            if (current != null) current.removeView(view);
            parent.addView(view, index);
        }
        layoutChildren(parent);
        if (current != null && current != parent) layoutChildren(current);
        if (focus != null) focus.requestFocus();
    }
    private void remove(Node node) {
        if (node.view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup)node.view;
            while (group.getChildCount() > 0) remove(need(String.valueOf(group.getChildAt(0).getTag())));
        }
        ViewGroup parent = node.view.getParent() instanceof ViewGroup ? (ViewGroup)node.view.getParent() : null;
        if (parent != null) { parent.removeView(node.view); layoutChildren(parent); }
        nodes.remove(node.key);
    }
    private Node tree(JSONObject descriptor) throws JSONException {
        String key = descriptor.getString("key"), kind = descriptor.getString("kind");
        Node node = nodes.get(key);
        if (node != null && !node.kind.equals(kind)) { remove(node); node = null; }
        if (node == null) node = create(key, kind, descriptor.getJSONObject("props"));
        node.action = descriptor.optString("action"); node.actionId = descriptor.optLong("action_id");
        node.text = descriptor.optString("text"); node.hidden = descriptor.optBoolean("hidden");
        properties(node, descriptor.getJSONObject("props"));
        if (node.view instanceof Switch) {
            node.changing = true; ((Switch)node.view).setChecked(descriptor.optBoolean("checked")); node.changing = false;
        }
        JSONArray children = descriptor.getJSONArray("children");
        Set<String> wanted = new HashSet<>(); String after = "";
        for (int i = 0; i < children.length(); i++) {
            Node child = tree(children.getJSONObject(i)); position(child, key, after); after = child.key; wanted.add(child.key);
        }
        if (node.view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup)node.view;
            for (int i = group.getChildCount() - 1; i >= 0; i--) {
                String child = String.valueOf(group.getChildAt(i).getTag());
                if (!wanted.contains(child)) remove(need(child));
            }
        }
        return node;
    }
    void apply(JSONObject packet) throws JSONException {
        if (Looper.myLooper() != Looper.getMainLooper()) throw new IllegalStateException("UI patches require the main thread");
        if (packet.getInt("version") != 1) throw new IllegalArgumentException("Unsupported Flexscript UI ABI");
        ArrayList<ScrollView> following=new ArrayList<>();
        for (Node node:nodes.values()) if (node.view instanceof ScrollView && node.view.isShown() && number(node.props,"follow",0)>0) {
            ScrollView scroll=(ScrollView)node.view;
            if (scroll.getChildCount()==0 || scroll.getChildAt(0).getHeight()-(scroll.getScrollY()+scroll.getHeight())<dp(100)) following.add(scroll);
        }
        View focused = findFocus();
        int selectionStart = -1, selectionEnd = -1;
        String focusedText = null;
        if (focused instanceof EditText) {
            EditText input = (EditText)focused;
            selectionStart = input.getSelectionStart(); selectionEnd = input.getSelectionEnd();
            focusedText = input.getText().toString();
        }
        JSONArray ops = packet.getJSONArray("ops");
        for (int i = 0; i < ops.length(); i++) {
            JSONObject op = ops.getJSONObject(i); String kind = op.getString("op"), key = op.getString("key");
            if (kind.equals("insert")) { position(tree(op.getJSONObject("node")), op.getString("parent"), op.getString("after")); continue; }
            Node node = need(key);
            switch (kind) {
            case "remove": remove(node); break;
            case "move": position(node, op.getString("parent"), op.getString("after")); break;
            case "checked":
                node.changing = true; ((Switch)node.view).setChecked(op.getBoolean("value")); node.changing = false; break;
            case "hidden": node.hidden = op.getBoolean("value"); properties(node, node.props); break;
            case "text": case "placeholder": case "label": node.text = op.optString("value", ""); properties(node, node.props); break;
            case "attribute":
                String name = op.getString("name"); Object value = op.opt("value");
                if (name.equals("action")) node.action = value == JSONObject.NULL ? "" : String.valueOf(value);
                else if (name.equals("action_id")) node.actionId = value == JSONObject.NULL ? 0 : Long.parseLong(String.valueOf(value));
                else {
                    JSONObject props = new JSONObject(node.props.toString());
                    if (value == JSONObject.NULL) props.remove(name); else props.put(name, value);
                    properties(node, props); break;
                }
                properties(node, node.props); break;
            default: throw new IllegalArgumentException("Unsupported UI operation: " + kind);
            }
        }
        for (ScrollView scroll:following) scroll.postOnAnimation(() -> tail(scroll));
        Node survivor = focused == null ? null : nodes.get(String.valueOf(focused.getTag()));
        if (survivor != null && survivor.view == focused) {
            if (!focused.hasFocus()) focused.requestFocus();
            if (focused instanceof EditText && focusedText.equals(((EditText)focused).getText().toString())
                && selectionStart >= 0 && selectionEnd >= 0)
                ((EditText)focused).setSelection(selectionStart, selectionEnd);
        }
    }
}
