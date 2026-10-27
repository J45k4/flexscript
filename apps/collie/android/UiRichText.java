package org.flexscript.collie;

import android.graphics.Color;
import android.graphics.Typeface;
import android.text.*;
import android.text.style.*;
import org.json.*;

/** Native span adapter; parsing and syntax highlighting are supplied by Flexscript. */
final class UiRichText {
    interface Link { void open(String href); }
    static CharSequence spans(String encoded) throws JSONException {
        return spans(encoded, null);
    }
    static CharSequence spans(String encoded, Link link) throws JSONException {
        SpannableStringBuilder out = new SpannableStringBuilder();
        JSONArray runs = new JSONArray(encoded);
        for (int i=0; i<runs.length(); i++) {
            JSONObject run = runs.getJSONObject(i);
            int start=out.length(); out.append(run.getString("text")); int end=out.length();
            int style=run.optInt("style"), flags=Spanned.SPAN_EXCLUSIVE_EXCLUSIVE;
            if (start==end) continue;
            if ((style&1)!=0) out.setSpan(new StyleSpan(Typeface.BOLD),start,end,flags);
            if ((style&16)!=0) out.setSpan(new StyleSpan(Typeface.ITALIC),start,end,flags);
            if ((style&32)!=0) out.setSpan(new StrikethroughSpan(),start,end,flags);
            if ((style&2)!=0) out.setSpan(new TypefaceSpan("monospace"),start,end,flags);
            if ((style&4)!=0) out.setSpan(new RelativeSizeSpan(1.12f),start,end,flags);
            if ((style&8)!=0) out.setSpan(new RelativeSizeSpan(.88f),start,end,flags);
            if (run.has("color")) out.setSpan(new ForegroundColorSpan(Color.parseColor(run.getString("color"))),start,end,flags);
            if (run.has("href")) {
                String href=run.getString("href");
                if (link != null) out.setSpan(new ClickableSpan() {
                    @Override public void onClick(android.view.View widget) { link.open(href); }
                },start,end,flags);
            }
        }
        return out;
    }
}
