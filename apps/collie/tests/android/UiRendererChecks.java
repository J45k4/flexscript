package org.flexscript.collie;

import android.app.Activity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.*;
import org.json.*;

/** Debug APK only: apply the compiler's actual cross-platform patch fixture. */
public final class UiRendererChecks {
    private static void check(boolean ok, String message) {
        if (!ok) throw new IllegalStateException(message);
    }
    private static void richText(Activity owner,ViewGroup mount) throws Exception {
        JSONObject[] state={new JSONObject()}, effect={new JSONObject()};
        UiRenderer[] renderer=new UiRenderer[1];
        renderer[0]=new UiRenderer(owner,event -> {
            try {
                JSONObject reply=((MainActivity)owner).uiCall(new JSONObject().put("action","event").put("state",state[0]).put("event",event));
                state[0]=reply.getJSONObject("state");effect[0]=reply.getJSONObject("command");renderer[0].apply(reply);
            } catch(Exception error) {throw new IllegalStateException(error);}
        });
        UiRenderer ui=renderer[0];mount.addView(ui,new ViewGroup.LayoutParams(-1,-1));
        try {
            String text="## Heading\n**Bold** *italic* ~~old~~ `inline` [Document](notes/report%20one.txt#L2) [Web](https://example.com/).\n\n| Name | Detail | Count |\n| :--- | :---: | ---: |\n| Alice | A long cell wraps without losing any of its actual content | 42 |\n\nAfter the table.\n```flexscript\nfn main(){return 42;}\n```\n";
            JSONObject packet=((MainActivity)owner).uiCall(new JSONObject().put("reset",true).put("action","update").put("data",new JSONObject().put("platform","android").put("cards",new JSONArray().put(new JSONObject().put("kind","assistant").put("text",text)))));
            state[0]=packet.getJSONObject("state");ui.apply(packet);
            TextView paragraph=(TextView)ui.widget("card-0-body-block-0");
            android.text.Spanned spans=(android.text.Spanned)paragraph.getText();String plain=spans.toString();
            check(!plain.contains("**") && plain.startsWith("Heading\nBold italic old inline"),"Markdown delimiters leaked into native text");
            check(spans.getSpans(plain.indexOf("Bold"),plain.indexOf("Bold")+4,android.text.style.StyleSpan.class).length>0,"native bold spans missing");
            check(spans.getSpans(plain.indexOf("italic"),plain.indexOf("italic")+6,android.text.style.StyleSpan.class)[0].getStyle()==android.graphics.Typeface.ITALIC,"native italic spans missing");
            check(spans.getSpans(0,spans.length(),android.text.style.StrikethroughSpan.class).length==1,"native strike spans missing");
            TextView code=(TextView)ui.widget("card-0-body-block-2");android.text.Spanned codeSpans=(android.text.Spanned)code.getText();
            check(codeSpans.toString().contains("fn main(){return 42;}") && codeSpans.getSpans(0,codeSpans.length(),android.text.style.TypefaceSpan.class).length>0,"fenced code after table missing");
            HorizontalScrollView scroll=(HorizontalScrollView)ui.widget("card-0-body-block-1-scroll");
            int width=Math.round(340*owner.getResources().getDisplayMetrics().density);
            ui.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(2000,View.MeasureSpec.EXACTLY));ui.layout(0,0,width,2000);
            check(scroll.getChildAt(0).getWidth()>scroll.getWidth(),"wide table did not retain horizontal overflow");scroll.scrollTo(100,0);check(scroll.getScrollX()>0,"native table cannot scroll horizontally");
            TextView count=(TextView)ui.widget("card-0-body-block-1-row-1-cell-2");check(count.getText().toString().equals("42") && (count.getGravity()&android.view.Gravity.RELATIVE_HORIZONTAL_GRAVITY_MASK)==android.view.Gravity.END,"table cell text/alignment missing");
            android.text.style.ClickableSpan[] links=spans.getSpans(0,spans.length(),android.text.style.ClickableSpan.class);check(links.length==2,"file/web clickable spans missing");
            links[0].onClick(paragraph);check(effect[0].getString("kind").equals("open_link") && effect[0].getString("href").equals("notes/report%20one.txt#L2"),"native file tap bypassed shared rendered-link validation");
            links[1].onClick(paragraph);check(effect[0].getString("href").equals("https://example.com/"),"native web tap lost its actual target");
            ui.widget("card-0-body-block-1-copy").performClick();check(effect[0].getString("kind").equals("copy") && effect[0].getString("text").startsWith("Name\tDetail\tCount\nAlice\t"),"native table copy is not selectable TSV content");
        } finally {mount.removeView(ui);}
    }
    public static JSONObject run(Activity owner, ViewGroup mount, JSONArray packets) throws Exception {
        JSONArray events = new JSONArray();
        UiRenderer ui = new UiRenderer(owner, events::put);
        mount.addView(ui, new ViewGroup.LayoutParams(-1, -1));
        try {
            ui.apply(packets.getJSONObject(0));
            View heading = ui.findViewWithTag("heading");
            EditText field = ui.findViewWithTag("input-2");
            field.setText("local draft"); field.requestFocus(); field.setSelection(2, 6);
            check(field.hasFocus(), "fixture could not focus initial editor");
            // Clear the input's genuine change event before testing update suppression.
            int count = events.length();
            ui.apply(packets.getJSONObject(1)); ui.apply(packets.getJSONObject(2)); ui.apply(packets.getJSONObject(3));
            check(ui.findViewWithTag("heading") == heading, "static widget identity");
            check(ui.findViewWithTag("input-2") == field && field.getText().toString().equals("local draft") && field.hasFocus() && field.getSelectionStart()==2 && field.getSelectionEnd()==6, "keyed move lost input identity/draft/focus/selection");
            LinearLayout rows = ui.findViewWithTag("rows");
            check(rows.getChildAt(0).getTag().equals("row-2") && rows.getChildAt(1).getTag().equals("row-1"), "keyed order");
            check(ui.findViewWithTag("branch") instanceof Button && ui.findViewWithTag("hidden").getVisibility()==View.GONE, "replacement/visibility");
            check(events.length()==count, "programmatic patches generated input events");
            ui.findViewWithTag("act").performClick();
            JSONObject event = events.getJSONObject(events.length()-1);
            check(event.getString("action").equals("changed") && event.getLong("action_id")==2 && event.getString("key").equals("act"), "updated action binding");
            ui.apply(packets.getJSONObject(4)); ui.apply(packets.getJSONObject(5));
            check(ui.findViewWithTag("input-2")==field && ui.findViewWithTag("row-1")==null && ui.findViewWithTag("input-3")!=null, "insert/remove survival");
            ui.apply(packets.getJSONObject(6));
            check(rows.getChildCount()==0 && ui.findViewWithTag("input-2")==null, "recursive removal");
            ui.apply(packets.getJSONObject(7));
            EditText draft = ui.findViewWithTag("draft");
            draft.setText("keep across snapshot"); draft.requestFocus(); draft.setSelection(1,5);
            ui.apply(packets.getJSONObject(8));
            check(ui.findViewWithTag("draft")==draft && draft.getText().toString().equals("keep across snapshot") && draft.hasFocus() && draft.getSelectionStart()==1 && draft.getSelectionEnd()==5, "snapshot lost draft/focus/selection");
            ui.apply(packets.getJSONObject(9));
            check(draft.getText().toString().equals("controlled") && ((TextView)ui.findViewWithTag("value")).getText().toString().equals("5"), "controlled value/text");
            java.lang.reflect.Field engineField=MainActivity.class.getDeclaredField("ENGINE");
            engineField.setAccessible(true); Object engineLock=engineField.get(null);
            java.util.concurrent.CountDownLatch held=new java.util.concurrent.CountDownLatch(1);
            Thread holder=new Thread(() -> {
                synchronized(engineLock) { held.countDown(); try { Thread.sleep(1500); } catch(InterruptedException ignored) {} }
            });
            holder.start(); check(held.await(2,java.util.concurrent.TimeUnit.SECONDS),"engine lock fixture");
            long before=android.os.SystemClock.elapsedRealtime();
            JSONObject summary=((MainActivity)owner).uiCall(new JSONObject().put("action","summary").put("saved",new JSONObject()));
            long elapsed=android.os.SystemClock.elapsedRealtime()-before;
            holder.join(2000);
            check(elapsed<700 && summary.has("title"),"UI evaluation waited for agent engine lock: "+elapsed);
            // Round-trip each real editor event through the production reducer.
            // Updating the controlled value must leave the KeyListener intact.
            final JSONObject[] state={new JSONObject()};
            final UiRenderer[] live={null};
            live[0]=new UiRenderer(owner,e -> {
                try {
                    JSONObject reply=((MainActivity)owner).uiCall(new JSONObject().put("state",state[0]).put("action","event").put("event",e));
                    state[0]=reply.getJSONObject("state");live[0].apply(reply);
                } catch(Exception error) { throw new IllegalStateException(error); }
            });
            mount.addView(live[0],new ViewGroup.LayoutParams(-1,-1));
            try {
                JSONObject initial=((MainActivity)owner).uiCall(new JSONObject().put("reset",true).put("action","update").put("data",new JSONObject().put("page","conversations")));
                state[0]=initial.getJSONObject("state");live[0].apply(initial);
                EditText search=(EditText)live[0].widget("conversations-query");search.requestFocus();
                android.text.method.KeyListener keys=search.getKeyListener();int type=search.getInputType();
                int capFlags=android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES|android.text.InputType.TYPE_TEXT_FLAG_CAP_WORDS|android.text.InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS;
                check((type&capFlags)==0,"shared search input unexpectedly capitalizes identifiers");
                for(int code=android.view.KeyEvent.KEYCODE_A;code<=android.view.KeyEvent.KEYCODE_C;code++) {
                    search.dispatchKeyEvent(new android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN,code));
                    search.dispatchKeyEvent(new android.view.KeyEvent(android.view.KeyEvent.ACTION_UP,code));
                    check(search.getKeyListener()==keys && search.getInputType()==type,"controlled echo changed editor input configuration");
                    check(search.hasFocus(),"controlled echo lost editor focus");
                }
                check(search.getText().toString().equals("abc"),"controlled echo lost keyboard input: "+search.getText());
                check(state[0].getString("query").equals("abc"),"shared reducer lost editor state");
                JSONObject chat=((MainActivity)owner).uiCall(new JSONObject().put("state",state[0]).put("action","update").put("data",new JSONObject().put("page","chat")));live[0].apply(chat);
                EditText composer=(EditText)live[0].widget("composer-draft");check((composer.getInputType()&capFlags)==android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES,"shared chat input lost its declared sentence-capitalization hint");
            } finally {mount.removeView(live[0]);}
            richText(owner,mount);
            return new JSONObject().put("ok",true).put("checks",19);
        } finally { mount.removeView(ui); }
    }
}
