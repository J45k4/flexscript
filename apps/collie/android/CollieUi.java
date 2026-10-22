package org.flexscript.collie;

import android.os.Looper;
import java.io.File;
import org.json.*;

/** Android frame/event adapter. Every screen and interaction is in ui/app.flex. */
final class CollieUi {
    final UiRenderer page;
    private final MainActivity host;
    private File workspace;
    private JSONObject state=new JSONObject(), pending=new JSONObject();
    private JSONArray appended=new JSONArray();
    private boolean scheduled, initialized;
    private Object streamToken;

    CollieUi(MainActivity owner) {
        host=owner;
        page=new UiRenderer(owner,event -> { flush(); call("event",object("event",event)); });
    }
    static JSONObject object(String key,Object value) {
        try { return new JSONObject().put(key,value); }
        catch (JSONException error) { throw new IllegalArgumentException(error); }
    }
    void workspace(File value) { workspace=value; page.workspace(value); }
    private void call(String action,JSONObject extras) {
        if (workspace==null || host.platformClosed()) return;
        try {
            JSONObject request=new JSONObject(extras.toString()).put("action",action).put("state",state).put("reset",!initialized);
            JSONObject reply=host.uiCall(request);
            state=reply.getJSONObject("state"); page.apply(reply); initialized=true;
            host.uiEffect(reply.getJSONObject("command"));
        } catch (Exception error) {
            android.util.Log.e("Collie", "UI bridge failed", error);
            // Platform failures feed the same shared notice view. Avoid a
            // recursive render if the compiler/renderer itself is unavailable.
            if (initialized && !action.equals("notice")) call("notice",object("text",MainActivity.safe(error)));
        }
    }
    private void onMain(Runnable action) {
        if (Looper.myLooper()==Looper.getMainLooper()) action.run(); else host.runOnUiThread(action);
    }
    void update(JSONObject facts) {
        onMain(() -> {
            try {
                java.util.Iterator<String> keys=facts.keys();
                while(keys.hasNext()) { String key=keys.next(); pending.put(key,facts.get(key)); }
                schedule();
            } catch (JSONException error) { throw new IllegalArgumentException(error); }
        });
    }
    private void schedule() {
        if (scheduled) return;
        scheduled=true; page.postOnAnimation(this::flush);
    }
    private void flush() {
        scheduled=false;
        if (pending.length()==0 && appended.length()==0) return;
        JSONObject request=object("data",pending);
        try { if(appended.length()>0) request.put("append_cards",appended); }
        catch(JSONException error) { throw new IllegalArgumentException(error); }
        pending=new JSONObject(); appended=new JSONArray(); call("update",request);
    }
    void clear() { onMain(() -> { flush(); streamToken=null; call("clear",new JSONObject()); }); }
    void cards(JSONArray cards) { onMain(() -> { appended=new JSONArray(); update(object("cards",cards)); }); }
    void render(JSONObject card) { onMain(() -> { appended.put(card); schedule(); }); }
    void working(boolean value) { update(object("busy",value)); }
    void status(String text) { update(object("status",text)); }
    void context(String model,long used,long total,boolean estimated) {
        try { update(new JSONObject().put("model",model).put("used",used).put("total",total).put("estimated",estimated).put("context_unavailable",false)); }
        catch(JSONException error) { throw new IllegalArgumentException(error); }
    }
    void contextUnavailable() { update(object("context_unavailable",true)); }
    void continuation(boolean value) { update(object("continuation",value)); }
    void attachments(JSONArray files) { update(object("attachments",files)); }
    void workers(JSONArray rows,String error) {
        try { update(new JSONObject().put("workers",rows).put("workers_error",error)); }
        catch(JSONException failure) { throw new IllegalArgumentException(failure); }
    }
    Object beginStream() { streamToken=new Object(); return streamToken; }
    void stream(Object token,String text) { if (token==streamToken) update(object("stream",text)); }
    void removeStream() { streamToken=null; update(object("stream","")); }
    void toBottom(boolean force) { page.bottom("chat-scroll",force); }
    void back() { flush(); call("back",new JSONObject()); }
    void notice(String text) { onMain(() -> { flush(); call("notice",object("text",text)); }); }
    void preview(JSONObject file) { onMain(() -> { flush(); call("preview",object("file",file)); }); }
    void restore(JSONObject navigation) { onMain(() -> { flush(); call("restore",object("data",navigation)); }); }
    JSONObject navigation() {
        flush();
        try { return host.uiCall(new JSONObject().put("action","navigation").put("state",state)); }
        catch(Exception error) { return new JSONObject(); }
    }
    String page() { return state.optString("page","chat"); }
}
