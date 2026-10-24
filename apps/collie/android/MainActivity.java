package org.flexscript.collie;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.net.Uri;
import android.os.Bundle;
import android.util.AtomicFile;
import android.view.View;
import android.view.WindowInsets;
import android.widget.*;
import java.io.*;
import java.net.URL;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import javax.net.ssl.HttpsURLConnection;
import org.json.*;

/**
 * Android owns lifecycle, TLS and widgets. Shared Flexscript owns the protocol,
 * compiler, checked VM, database, limits and compaction format.
 */
public class MainActivity extends Activity {
    static {
        System.loadLibrary("collie");
        System.loadLibrary("collie_ui");
    }
    private static native long nativeCall(
        long op, ByteBuffer input, long size, ByteBuffer output, ByteBuffer session);
    private static native long nativeUiCall(ByteBuffer input,long size,ByteBuffer output);
    private static native void nativeCancel();
    private static native void nativeBegin();
    // Called synchronously by the trusted native broker, never by raw guest FFI.
    private static byte[] vmHttpGet(byte[] url) { return VmInternet.get(url); }
    private static byte[] vmHardware(byte[] request) { return VmHardware.call(request); }
    private static byte[] vmViewImage(byte[] bytes) { return VmViews.capture(bytes); }
    private static byte[] vmImageBytes(byte[] id) {
        try {
            return VmViews.snapshotBytes(id);
        } catch (Exception e) {
            return null;
        }
    }
    private static final Object ENGINE = new Object(), UI_ENGINE = new Object();
    private static final ByteBuffer UI_OUTPUT = ByteBuffer.allocateDirect(8*1024*1024);
    private static final int LIMIT = 8 * 1024 * 1024;
    private static final ByteBuffer NATIVE_OUTPUT = ByteBuffer.allocateDirect(LIMIT);
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private volatile boolean stopped, busy, destroyed;
    private volatile HttpsURLConnection connection;
    private volatile Thread nativeThread, turnThread;
    private CollieUi ui;
    private FrameLayout navigation;
    private WorkerManager workers;
    private String lastWorkers = "";
    private android.window.OnBackInvokedCallback uiBack;
    private JSONObject pendingExecution;
    private JSONObject harness = new JSONObject();
    private PlatformTask activeTask;
    final HardwareConsent hardwareConsent = new HardwareConsent(this);
    volatile boolean hardwareVisible,hardwareResumed;
    final PermissionPrompts permissionPrompts = new PermissionPrompts(this);
    private volatile JSONObject permissions = new JSONObject();
    private volatile HardwareNetwork.ModelRoute modelRoute;
    private String modelNetwork = "default";
    private String model = "gpt-6.1-sol", sessionId;
    private File session;
    private JSONArray messages = new JSONArray(), archive = new JSONArray(),
                      cards = new JSONArray();
    private JSONArray pendingAttachments = new JSONArray();
    private JSONObject usage;
    private int anchor;

    private static ByteBuffer buffer(byte[] bytes, boolean nul) {
        ByteBuffer b = ByteBuffer.allocateDirect(bytes.length + (nul ? 1 : 0));
        b.put(bytes);
        if (nul)
            b.put((byte) 0);
        b.rewind();
        return b;
    }
    private JSONObject engine(int op, JSONObject request) throws Exception {
        return engineAt(session, op, request);
    }
    JSONObject engineAt(File workspace, int op, JSONObject request) throws Exception {
        byte[] input = request.toString().getBytes(StandardCharsets.UTF_8);
        ByteBuffer out = NATIVE_OUTPUT;
        long n;
        byte[] bytes;
        synchronized (ENGINE) {
            out.clear();
            nativeThread = Thread.currentThread();
            nativeBegin();
            if (request.optBoolean("_cancel_before_run"))
                nativeCancel();
            if (op == 3) { VmInternet.begin();VmHardware.startProgram(); }
            VmViews.begin(workspace);VmHardware.begin(this,workspace);
            try {
                n = nativeCall(
                    op, buffer(input, true), input.length, out,
                    buffer(workspace.getAbsolutePath().getBytes(StandardCharsets.UTF_8), true));
                if (n < 0 || n > LIMIT)
                    throw new IOException("Native engine failed (" + n + ").");
                bytes = new byte[(int)n];
                out.get(bytes);
            } finally {
                VmViews.end();VmHardware.end();
                nativeThread = null;
            }
        }

        JSONObject result = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
        if (result.has("error"))
            throw new IOException(result.getString("error"));
        return result;
    }
    JSONObject uiCall(JSONObject request) throws Exception {
        byte[] input=request.toString().getBytes(StandardCharsets.UTF_8), bytes;
        synchronized(UI_ENGINE) {
            UI_OUTPUT.clear();long size=nativeUiCall(buffer(input,true),input.length,UI_OUTPUT);
            if(size<0 || size>LIMIT) throw new IOException("Native UI failed ("+size+").");
            bytes=new byte[(int)size];UI_OUTPUT.get(bytes);
        }
        JSONObject result=new JSONObject(new String(bytes,StandardCharsets.UTF_8));
        if(result.has("error")) throw new IOException(result.getString("error"));
        return result;
    }
    JSONObject workerConfig(File workspace, long id) throws JSONException {
        return new JSONObject()
            .put("model", model)
            .put("permissions", new JSONObject(permissions.toString()))
            .put("agent_id", id)
            .put("workspace_file", new File(workspace, "agent.flexdb").getAbsolutePath());
    }
    private JSONObject loadPermissions(Object saved) throws Exception {
        JSONObject result = engine(8, new JSONObject()
                                          .put("config", config())
                                          .put("action", "permissions")
                                          .put("saved", saved == null ? JSONObject.NULL : saved));
        return result.getJSONObject("policy");
    }
    boolean workersAllowed() { return permissions.optBoolean("workers"); }
    boolean permissionNeedsPrompt(String key) { return "ask".equals(permissions.opt(key)); }
    boolean ownsPermissionRequest(File workspace) { return workspace.equals(session) && !destroyed; }
    void showPermissionRequest(JSONObject request) {
        if (!destroyed) ui.update(CollieUi.object("permission_request",request));
    }
    void savePermission(String key,Object value) throws Exception {
        JSONObject previous=permissions;
        try {
            boolean backgroundCleanupFailed=false;
            if(key.equals("nfc")&&!Boolean.TRUE.equals(value)){
                try{HardwareHceBackground.revoke(this,session);}
                catch(Exception cleanup){backgroundCleanupFailed=true;}
            }
            permissions=new JSONObject(previous.toString()).put(key,value);
            save();if(!Boolean.TRUE.equals(value)){
                // A running VM holds a configuration snapshot. Stop it on an
                // actual revocation so it cannot reopen devices with old grants.
                // Permission dialogs resume outside nativeCall and keep their
                // ordinary denied-call result rather than being cancelled.
                if(Boolean.TRUE.equals(previous.opt(key))&&nativeThread!=null){nativeCancel();VmInternet.cancel();VmHardware.cancel();}
                VmHardware.revoke(session,key);
            }updateUiFacts();if(backgroundCleanupFailed)ui.notice("NFC access is disabled. Android could not finish removing the background card.");
        } catch(Exception error) { permissions=previous;updateUiFacts();throw error; }
    }
    boolean hasAuthentication() {
        return new File(getFilesDir(), "credentials/auth.json").isFile();
    }
    private JSONObject config() throws JSONException {
        return new JSONObject()
            .put("model", model)
            .put("agent_id", 0)
            .put("permissions", new JSONObject(permissions.toString()))
            .put("workspace_file", new File(session, "agent.flexdb").getAbsolutePath());
    }
    private JSONObject request() throws JSONException {
        return new JSONObject().put("config", config()).put("messages", messages);
    }
    private int dp(int v) {
        return (int) (v * getResources().getDisplayMetrics().density + .5f);
    }
    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);
        synchronized (ENGINE) {
            nativeBegin();
            VmInternet.begin();
        }
        ui = new CollieUi(this);
        navigation = new FrameLayout(this);
        navigation.addView(ui.page, new FrameLayout.LayoutParams(-1,-1));
        setContentView(navigation);
        if (android.os.Build.VERSION.SDK_INT >= 29) getWindow().setNavigationBarContrastEnforced(false);
        ui.page.setOnApplyWindowInsetsListener((view,insets) -> {
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                android.graphics.Insets bars=insets.getInsets(WindowInsets.Type.systemBars());
                view.setPadding(bars.left,bars.top,bars.right,
                    Math.max(bars.bottom,insets.getInsets(WindowInsets.Type.ime()).bottom));
            } else view.setPadding(insets.getSystemWindowInsetLeft(),insets.getSystemWindowInsetTop(),
                                   insets.getSystemWindowInsetRight(),insets.getSystemWindowInsetBottom());
            return insets;
        });
        model = getPreferences(0).getString("model", "gpt-6.1-sol");
        modelNetwork=getPreferences(0).getString("model_network","default");
        try{modelRoute=new HardwareNetwork.ModelRoute(this,modelNetwork);}catch(Exception error){modelNetwork="default";try{modelRoute=new HardwareNetwork.ModelRoute(this,modelNetwork);}catch(Exception ignored){}}
        try {
            String id=getPreferences(0).getString("session",null);
            if (id==null) newSession(); else loadSession(id);
        } catch(Exception error) { newSession(); showError("Previous session could not be loaded: "+safe(error)); }
        if (state!=null) {
            try { String saved=state.getString("ui_navigation"); if(saved!=null) ui.restore(new JSONObject(saved)); }
            catch(JSONException ignored) {}
        }
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            uiBack=ui::back;
            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT,uiBack);
        }
        HardwareWifi.recoverAsync(this);
        HardwareHce.recoverAsync(this);
        onTestIntent(getIntent());
        permissionRationale(getIntent());
    }
    @Override
    public boolean dispatchTouchEvent(android.view.MotionEvent event){HardwareInput.motion(this,event,1);return super.dispatchTouchEvent(event);}
    @Override
    public boolean dispatchGenericMotionEvent(android.view.MotionEvent event){HardwareInput.motion(this,event,4);return super.dispatchGenericMotionEvent(event);}
    @Override
    public boolean dispatchKeyEvent(android.view.KeyEvent event){HardwareInput.key(this,event);return super.dispatchKeyEvent(event);}
    @Override
    protected void onStart(){super.onStart();hardwareVisible=true;}
    @Override
    protected void onResume(){super.onResume();hardwareResumed=true;}
    @Override
    protected void onPause(){hardwareResumed=false;HardwareHce.hidden();super.onPause();}
    @Override
    protected void onStop(){hardwareVisible=false;VmHardware.appHidden();super.onStop();}
    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        onTestIntent(intent);
        permissionRationale(intent);
    }
    private void permissionRationale(Intent intent) {
        if(intent!=null && ("android.intent.action.VIEW_PERMISSION_USAGE".equals(intent.getAction()) || "androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE".equals(intent.getAction()))) ui.healthRationale();
    }
    private void prepareSession(String id) throws IOException {
        if (!id.matches("[A-Za-z0-9-]{1,80}"))
            throw new IOException("Invalid session ID.");
        if (workers != null)
            workers.close();
        if(session!=null)VmHardware.closeWorkspace(session);
        sessionId = id;
        session = new File(getFilesDir(), "workspaces/" + id);
        ui.workspace(session);
        if (!new File(session, "files").isDirectory() && !new File(session, "files").mkdirs())
            throw new IOException("Cannot create workspace.");
        getPreferences(0).edit().putString("session", id).apply();
    }
    private void newSession() {
        if (busy)
            return;
        try {
            prepareSession(UUID.randomUUID().toString());
            permissions = loadPermissions(null);
            harness = new JSONObject();
            messages = new JSONArray();
            archive = new JSONArray();
            cards = new JSONArray();
            pendingAttachments = new JSONArray();
            refreshAttachments();
            usage = null;
            anchor = 0;
            pendingExecution = null;
            ui.clear();
            ui.continuation(false);
            save();
            addCard("info",
                "App-private workspace ready. Import ChatGPT auth.json from Menu to connect.");
            startWorkers();
            updateUiFacts();
            updateContext();
        } catch (Exception e) {
            showError(safe(e));
        }
    }
    private void loadSession(String id) throws Exception {
        prepareSession(id);
        File file = new File(session, "session.json");
        if (file.isFile()) {
            JSONObject saved = new JSONObject(read(new FileInputStream(file), LIMIT));
            harness = saved;
            permissions = loadPermissions(saved.opt("permissions"));
            messages = saved.getJSONArray("messages");
            archive = saved.optJSONArray("archive");
            if (archive == null)
                archive = new JSONArray();
            cards = saved.optJSONArray("cards");
            if (cards == null)
                cards = new JSONArray();
            pendingAttachments = saved.optJSONArray("pending_attachments");
            if (pendingAttachments == null) pendingAttachments = new JSONArray();
            usage = saved.optJSONObject("usage");
            anchor = saved.optInt("anchor", 0);
            pendingExecution = saved.optJSONObject("pending_execution");
        } else {
            permissions = loadPermissions(null);
            messages = new JSONArray();
            archive = new JSONArray();
            cards = new JSONArray();
            pendingAttachments = new JSONArray();
            usage = null;
            anchor = 0;
            pendingExecution = null;
        }
        if (pendingExecution != null)
            pendingExecution.put("restored", true);
        runOnUiThread(() -> ui.continuation(pendingExecution != null));
        startWorkers();
        final JSONArray visible = new JSONArray(cards.toString());
        refreshAttachments();
        runOnUiThread(() -> { ui.clear(); ui.cards(visible); updateUiFacts(); });
        updateContext();
    }
    private void save() throws Exception {
        JSONObject data = snapshotConversation()
                              .put("messages", messages)
                              .put("archive", archive)
                              .put("cards", cards)
                              .put("pending_attachments", pendingAttachments)
                              .put("permissions", permissions)
                              .put("anchor", anchor);
        if (usage != null)
            data.put("usage", usage);
        if (pendingExecution != null)
            data.put("pending_execution", pendingExecution);
        else
            data.remove("pending_execution");
        atomic(new File(session, "session.json"), data.toString());
    }
    static void atomic(File file, String text) throws IOException {
        AtomicFile atomic = new AtomicFile(file);
        FileOutputStream out = null;
        try {
            out = atomic.startWrite();
            out.write(text.getBytes(StandardCharsets.UTF_8));
            atomic.finishWrite(out);
        } catch (IOException e) {
            if (out != null)
                atomic.failWrite(out);
            throw e;
        }
    }
    static String read(InputStream in, int limit) throws IOException {
        try (InputStream stream = in; ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] buf = new byte[8192];
            int n;
            while ((n = stream.read(buf)) != -1) {
                if (out.size() + n > limit)
                    throw new IOException("File exceeds size limit.");
                out.write(buf, 0, n);
            }
            return new String(out.toByteArray(), StandardCharsets.UTF_8);
        }
    }
    private void renderCard(JSONObject card) {
        ui.render(card);
    }
    private void addResult(JSONObject observation) {
        try {
            JSONObject card = new JSONObject()
                                  .put("kind", "result")
                                  .put("text", resultText(observation))
                                  .put("observation", observation);
            cards.put(card);
            runOnUiThread(() -> renderCard(card));
        } catch (JSONException impossible) {
            throw new IllegalStateException(impossible);
        }
    }
    private void addCard(String kind, String value) {
        try {
            JSONObject card = new JSONObject().put("kind", kind).put("text", value);
            cards.put(card);
            runOnUiThread(() -> renderCard(card));
        } catch (JSONException impossible) {
            throw new IllegalStateException(impossible);
        }
    }
    private void showError(String value) {
        addCard("error", value);
    }
    private void working(boolean value) {
        busy = value;
        runOnUiThread(() -> ui.working(value));
    }
    private void cancel() {
        stopped = true;
        PlatformTask task = activeTask;
        if (task != null)
            task.cancel();
        if (nativeThread == turnThread) {
            nativeCancel();
            VmInternet.cancel();VmHardware.cancel();
        }
        HttpsURLConnection c = connection;
        if (c != null)
            c.disconnect();
        ui.status("Stopping…");
    }
    private void checkStop() throws IOException {
        if (stopped || destroyed)
            throw new IOException("Cancelled.");
    }
    private void begin(Runnable action) {
        if (busy)
            return;
        VmInternet.begin();
        working(true);
        stopped = false;
        nativeBegin();
        worker.execute(() -> {
            turnThread = Thread.currentThread();
            try {
                action.run();
            } catch (Exception e) {
                showError(safe(e));
            } finally {
                try {
                    save();
                } catch (Exception e) {
                    showError("Cannot save session: " + safe(e));
                }
                if (!destroyed)
                    nativeBegin();
                turnThread = null;
                working(false);
                updateContext();
            }
        });
    }
    private void submit(String text) {
        if (busy || (text.isEmpty() && pendingAttachments.length()==0)) return;
        final JSONArray attached=pendingAttachments;
        begin(() -> {
            try { if (pendingExecution!=null) continueTurn(null); turn(text,null,attached); }
            catch(Exception error) { throw new RuntimeException(error); }
        });
    }
    private JSONObject authentication() throws Exception {
        File f = new File(getFilesDir(), "credentials/auth.json");
        if (!f.isFile())
            throw new IOException("Import ChatGPT auth.json from Menu first.");
        JSONObject auth = new JSONObject(read(new FileInputStream(f), 1048576));
        return validateAuth(auth);
    }
    private JSONObject validateAuth(JSONObject auth) throws Exception {
        return engine(8, new JSONObject()
                             .put("config", config())
                             .put("action", "authenticate")
                             .put("auth", auth));
    }
    static String safe(Throwable e) {
        while (e.getCause() != null) e = e.getCause();
        String text = e.getMessage();
        return text == null ? e.getClass().getSimpleName() : text;
    }
    JSONObject responseAt(JSONObject body, boolean compact, JSONArray fixture, int index,
                          File workspace, JSONObject baseRequest, PlatformTask job)
        throws Exception {
        if (job == null)
            checkStop();
        else
            job.check();
        final long streamId=baseRequest.getJSONObject("config").optLong("agent_id");
        final boolean feedback=baseRequest.optBoolean("feedback");
        Object token=null;
        if(!compact) {
            java.util.concurrent.FutureTask<Object> start=new java.util.concurrent.FutureTask<>(() -> ui.beginStream(streamId));
            runOnUiThread(start);token=start.get();
        }
        final Object preview=token;
        try {
        if (fixture != null) {
            if (index >= fixture.length())
                throw new IOException("Fixture ran out of responses.");
            JSONObject event = fixture.getJSONObject(index);
            JSONArray events=event.optJSONArray("_events");
            if(events!=null) {
                JSONObject stream=new JSONObject();
                for(int n=0;n<events.length();n++) {
                    int delay=Math.max(0,Math.min(20000,event.optInt("_event_delay_ms")));
                    for(int elapsed=0;elapsed<delay;elapsed+=100) { if(job==null) checkStop();else job.check();Thread.sleep(100); }
                    JSONObject processed=streamPacket(workspace,baseRequest,compact,stream,events.getJSONObject(n).toString(),streamId,preview,feedback);
                    stream=processed.getJSONObject("stream");
                    if(processed.optBoolean("complete")) return processed.getJSONObject("reply");
                }
                throw new IOException("Fixture stream ended without a completed response.");
            }
            if (job != null) {
                int delay = Math.max(0, Math.min(20000, event.optInt("_delay_ms")));
                for (int elapsed = 0; elapsed < delay; elapsed += 100) {
                    job.check();
                    Thread.sleep(100);
                }
            }
            return engineAt(workspace, compact ? 5 : 2,
                            new JSONObject(baseRequest.toString()).put("event", event));
        }
        JSONObject transport = authentication();
        HttpsURLConnection c =
            (HttpsURLConnection) (modelRoute==null?new URL(transport.getString("url")).openConnection():modelRoute.open(new URL(transport.getString("url"))));
        if (job == null)
            connection = c;
        else
            job.connection = c;
        c.setInstanceFollowRedirects(false);
        c.setConnectTimeout(transport.getInt("connect_timeout_ms"));
        c.setReadTimeout(transport.getInt("read_timeout_ms"));
        c.setRequestMethod(transport.getString("method"));
        c.setDoOutput(true);
        JSONObject headers = transport.getJSONObject("headers");
        for (java.util.Iterator<String> keys = headers.keys(); keys.hasNext();) {
            String key = keys.next();
            c.setRequestProperty(key, headers.getString(key));
        }
        byte[] data = body.toString().getBytes(StandardCharsets.UTF_8);
        if (data.length > LIMIT) throw new IOException("Model request exceeds 8 MiB. Compact context first.");
        c.setFixedLengthStreamingMode(data.length);
        try {
            if (job == null)
                checkStop();
            else
                job.check();
            try (OutputStream out = c.getOutputStream()) {
                out.write(data);
            }
            int statusCode = c.getResponseCode();
            if (statusCode != 200) {
                JSONObject error = engineAt(workspace, 8,
                                            new JSONObject()
                                                .put("config", baseRequest.getJSONObject("config"))
                                                .put("action", "transport_error")
                                                .put("status", statusCode));
                throw new IOException(error.getString("message"));
            }
            String type = c.getContentType();
            if (type != null
                && !type.toLowerCase(java.util.Locale.ROOT).startsWith("text/event-stream"))
                throw new IOException("Unexpected Codex response type.");
            try (InputStream in = c.getInputStream()) {
                ByteArrayOutputStream line = new ByteArrayOutputStream();
                StringBuilder event = new StringBuilder();
                JSONObject stream = new JSONObject();
                int total = 0;
                for (;;) {
                    if (job == null)
                        checkStop();
                    else
                        job.check();
                    int b = in.read();
                    if (b < 0)
                        throw new IOException("Codex stream ended without a completed response.");
                    if (++total > LIMIT)
                        throw new IOException("Model stream exceeds 8 MiB.");
                    if (b == 0)
                        throw new IOException("Invalid SSE stream.");
                    if (b != 10) {
                        line.write(b);
                        if (line.size() > 2097152)
                            throw new IOException("SSE line exceeds limit.");
                        continue;
                    }
                    String s = new String(line.toByteArray(), StandardCharsets.UTF_8);
                    line.reset();
                    if (s.endsWith("\r"))
                        s = s.substring(0, s.length() - 1);
                    if (s.startsWith("data:")) {
                        if (event.length() > 0)
                            event.append('\n');
                        event.append(s.substring(s.startsWith("data: ") ? 6 : 5));
                    } else if (s.isEmpty() && event.length() > 0) {
                        String json = event.toString();
                        event.setLength(0);
                        JSONObject processed = streamPacket(workspace,baseRequest,compact,stream,json,streamId,preview,feedback);
                        stream = processed.getJSONObject("stream");
                        if (processed.optBoolean("complete")) {
                            return processed.getJSONObject("reply");
                        }
                    }
                }
            }
        } finally {
            if (job == null)
                connection = null;
            else
                job.connection = null;
            c.disconnect();
        }
        } finally { if(preview!=null) runOnUiThread(() -> ui.removeStream(streamId,preview)); }
    }
    private JSONObject streamPacket(File workspace,JSONObject base,boolean compact,JSONObject stream,
                                    String event,long id,Object preview,boolean feedback) throws Exception {
        JSONObject packet=new JSONObject().put("config",base.getJSONObject("config"))
            .put("action","stream").put("stream",stream).put("event_json",event).put("compact",compact).put("feedback",feedback);
        if(compact) packet.put("messages",base.getJSONArray("messages"));
        JSONObject result=engineAt(workspace,8,packet);
        JSONObject visible=result.getJSONObject("display");
        if(preview!=null) runOnUiThread(() -> ui.stream(id,preview,visible));
        return result;
    }
    private JSONObject limits() throws Exception {
        JSONObject r = request().put("anchor", anchor);
        if (usage != null)
            r.put("usage", usage);
        JSONObject result = engine(6, r);

        return result;
    }
    private void updateContext() {
        if (destroyed)
            return;
        worker.execute(() -> {
            try {
                JSONObject l = limits();
                long n = l.getJSONObject("usage").optLong("total_tokens");
                boolean estimated = l.getJSONObject("usage").optBoolean("estimated");
                long total = l.getLong("usable_context_window");
                runOnUiThread(() -> ui.context(model, n, total, estimated));
            } catch (Exception e) {
                runOnUiThread(() -> ui.contextUnavailable());
            }
        });
    }
    private JSONObject snapshotConversation() throws JSONException {
        JSONObject state = new JSONObject(harness.toString())
                               .put("messages", messages)
                               .put("archive", archive)
                               .put("cards", cards)
                               .put("anchor", anchor)
                               .put("usage", usage == null ? JSONObject.NULL : usage)
                               .put("pending", JSONObject.NULL)
                               .put("pending_execution",
                                    pendingExecution == null ? JSONObject.NULL : pendingExecution);
        return state;
    }
    private void applyConversation(JSONObject state, JSONArray added) throws Exception {
        harness = state;
        messages = state.getJSONArray("messages");
        archive = state.getJSONArray("archive");
        cards = state.getJSONArray("cards");
        usage = state.optJSONObject("usage");
        anchor = state.optInt("anchor");
        pendingExecution = state.optJSONObject("pending_execution");
        save();
        runOnUiThread(() -> {
            for (int i = 0; i < added.length(); i++)
                try {
                    renderCard(added.getJSONObject(i));
                } catch (JSONException ignored) {
                }
            ui.continuation(pendingExecution != null && !busy);
        });
    }
    boolean platformClosed() { return destroyed; }
    private void runConversation(String action, JSONObject input, JSONArray fixture)
        throws Exception {
        PlatformTask task = new PlatformTask(this, session, 0, this::checkStop);
        activeTask = task;
        try {
            task.run(action, snapshotConversation(), input, fixture, this::applyConversation);
        } finally {
            activeTask = null;
        }
    }
    private void compact() throws Exception { runConversation("compact", new JSONObject(), null); }
    private void turn(String text, JSONArray fixture) throws Exception {
        turn(text, fixture, new JSONArray());
    }
    private void turn(String text, JSONArray fixture, JSONArray attached) throws Exception {
        if (fixture == null)
            authentication();
        if (attached == pendingAttachments) {
            pendingAttachments = new JSONArray();
            refreshAttachments();
        }
        runConversation("begin", new JSONObject().put("text", text).put("attachments", attached),
                        fixture);
    }
    private void continueTurn(JSONArray fixture) throws Exception {
        runConversation("resume", new JSONObject(), fixture);
    }
    private static String resultText(JSONObject r) {
        return r.optString("state") + " (exit " + r.optInt("exit_code", -1) + ")\n"
            + r.optString("stdout")
            + (r.optString("stderr").isEmpty() ? "" : "\n" + r.optString("stderr"))
            + (r.optBoolean("output_truncated") ? "\n[output truncated]" : "");
    }
    private void importLogin() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.setType("*/*");
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        startActivityForResult(intent, 1);
    }
    private void pickFile() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.setType("*/*");intent.addCategory(Intent.CATEGORY_OPENABLE);
        startActivityForResult(intent, 2);
    }
    private void pickPhoto() {
        Intent intent = new Intent("android.provider.action.PICK_IMAGES").setType("image/*");
        try { startActivityForResult(intent, 3); }
        catch (android.content.ActivityNotFoundException unavailable) {
            intent = new Intent(Intent.ACTION_OPEN_DOCUMENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE);
            startActivityForResult(intent, 3);
        }
    }
    private void takePhoto() {
        // A new explicit photo action replaces any interrupted pending capture,
        // including when its next Android permission request is declined.
        clearCameraCapture();
        if(checkSelfPermission(android.Manifest.permission.CAMERA)!=android.content.pm.PackageManager.PERMISSION_GRANTED){
            // This is the user's attachment action, independent of the agent's
            // conversation Camera grant. Do not create an output before consent.
            if(!getPreferences(0).edit().putString("manual_camera_session",sessionId).commit()){ui.notice("Cannot save the pending camera action.");return;}
            requestPermissions(new String[]{android.Manifest.permission.CAMERA},57);return;
        }
        takePhotoGranted();
    }
    private void takePhotoGranted() {
        String name = UUID.randomUUID().toString() + ".jpg";
        try {
            clearCameraCapture();
            if (!CameraAttachmentProvider.file(this, name).createNewFile())
                throw new IOException("Cannot create camera output.");
            getPreferences(0).edit().putString("camera_file", name).putString("camera_session", sessionId).commit();
            Uri uri = CameraAttachmentProvider.uri(name);
            Intent intent = new Intent(android.provider.MediaStore.ACTION_IMAGE_CAPTURE)
                .putExtra(android.provider.MediaStore.EXTRA_OUTPUT, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            intent.setClipData(android.content.ClipData.newRawUri("Camera attachment", uri));
            startActivityForResult(intent, 4);
        } catch (Exception error) {
            clearCameraCapture();
            ui.notice("Cannot open camera: " + safe(error));
        }
    }
    private void clearCameraCapture() {
        String name = getPreferences(0).getString("camera_file", null);
        getPreferences(0).edit().remove("camera_file").remove("camera_session").commit();
        if (name != null) {
            revokeUriPermission(CameraAttachmentProvider.uri(name), Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            try { CameraAttachmentProvider.file(this, name).delete(); } catch (IOException ignored) {}
        }
    }
    private void refreshAttachments() {
        final JSONArray files = pendingAttachments;
        runOnUiThread(() -> ui.attachments(files));
    }
    private void removeAttachment(int index) {
        if (busy || index < 0 || index >= pendingAttachments.length()) return;
        begin(() -> {
            try {
                String path = pendingAttachments.getJSONObject(index).getString("path");
                File root = new File(session, "files").getCanonicalFile();
                File file = new File(root, path.substring(1));
                if (!root.equals(file.getCanonicalFile().getParentFile()))
                    throw new IOException("Invalid attachment path.");
                if (file.exists() && !file.delete()) throw new IOException("Cannot remove attachment.");
                pendingAttachments.remove(index);
                refreshAttachments();
            } catch (Exception error) { throw new RuntimeException(error); }
        });
    }
    private String attachmentName(Uri uri) {
        String name = "imported-file";
        try (android.database.Cursor cursor = getContentResolver().query(uri,
            new String[] {android.provider.OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst() && !cursor.isNull(0)) name = cursor.getString(0);
        } catch (RuntimeException unavailable) { /* Providers may omit metadata. */ }
        return name;
    }
    private void copyPhoto(Uri uri, String name) throws Exception {
        File temporary = File.createTempFile("photo-import-", ".img", getCacheDir());
        try {
            try (InputStream in = getContentResolver().openInputStream(uri);
                 FileOutputStream out = new FileOutputStream(temporary)) {
                if (in == null) throw new IOException("Cannot open selected photo.");
                byte[] buffer = new byte[8192]; int n, total = 0;
                while ((n = in.read(buffer)) != -1) {
                    checkStop(); total += n;
                    if (total > 33554432) throw new IOException("Photos must be at most 32 MiB.");
                    out.write(buffer, 0, n);
                }
            }
            JSONObject preview;
            VmViews.begin(session);
            try { preview = new JSONObject(new String(VmViews.capturePhoto(temporary), StandardCharsets.UTF_8)); }
            finally { VmViews.end(); }
            if (preview.has("error")) throw new IOException(preview.getString("error"));
            checkStop();
            int dot = name.lastIndexOf('.');
            if (dot > 0) name = name.substring(0, dot);
            byte[] bytes = java.nio.file.Files.readAllBytes(VmViews.image(session, preview.getString("image_id")).toPath());
            storeAttachment(name + ".jpg", bytes, preview);
        } finally { temporary.delete(); }
    }
    private void copyWorkspaceFile(Uri uri) throws Exception {
        String name = attachmentName(uri);
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (InputStream input = getContentResolver().openInputStream(uri)) {
            if (input == null) throw new IOException("Cannot open selected file.");
            byte[] buffer = new byte[8192];int n;
            while ((n=input.read(buffer))!=-1) {
                checkStop();
                if (bytes.size()+n>2097152) throw new IOException("Imported files must be at most 2 MiB.");
                bytes.write(buffer,0,n);
            }
        }
        JSONObject attachment = new JSONObject();
        VmViews.begin(session);
        try {
            JSONObject preview = new JSONObject(new String(VmViews.capture(bytes.toByteArray()), StandardCharsets.UTF_8));
            if (!preview.has("error")) attachment = preview;
        } finally { VmViews.end(); }
        storeAttachment(name, bytes.toByteArray(), attachment);
    }
    private void storeAttachment(String name, byte[] bytes, JSONObject attachment) throws Exception {
        checkStop();
        if (pendingAttachments.length() >= 4) throw new IOException("Attach up to four files per message.");
        name = name.replaceAll("[^\\p{L}\\p{N}._ -]", "_");
        if (name.length() > 100) name = name.substring(0,100);
        if (name.isEmpty() || name.equals(".") || name.equals("..")) name = "imported-file";
        File root = new File(session,"files");File target = new File(root,name);
        int suffix=1;
        while (!target.createNewFile()) {
            if (suffix>1000) throw new IOException("Cannot choose an unused workspace filename.");
            target=new File(root,"import-"+(suffix++)+"-"+name);
        }
        try (FileOutputStream output = new FileOutputStream(target)) {output.write(bytes);output.getFD().sync();}
        catch (Exception error) {target.delete();throw error;}
        String path="/"+target.getName();
        attachment.put("path", path).put("file_bytes", bytes.length);
        pendingAttachments.put(attachment);
        refreshAttachments();
    }
    private void hideKeyboard() {
        ((android.view.inputmethod.InputMethodManager)getSystemService(INPUT_METHOD_SERVICE))
            .hideSoftInputFromWindow(navigation.getWindowToken(),0);
    }
    @Override public void onBackPressed() { ui.back(); }
    @Override protected void onSaveInstanceState(Bundle state) {
        super.onSaveInstanceState(state);
        state.putString("ui_navigation",ui.navigation().toString());
    }
    void waitingFor(long id) { runOnUiThread(() -> ui.status("Waiting for worker #"+id+"…")); }
    private void resumeMain() {
        if (busy || pendingExecution==null) return;
        begin(() -> { try { continueTurn(null); } catch(Exception error) { throw new RuntimeException(error); } });
    }
    private void startWorkers() {
        if (workers!=null) workers.close();
        lastWorkers="";
        workers=new WorkerManager(this,session,() -> runOnUiThread(this::refreshWorkers));
        refreshWorkers();
    }
    private void refreshWorkers() {
        if (destroyed || workers==null) return;
        JSONArray rows=workers.snapshot(); String error=workers.problem();
        String signature=rows.toString()+error;
        if (signature.equals(lastWorkers)) return;
        lastWorkers=signature; ui.workers(rows,error);
    }
    private void updateUiFacts() {
        try { ui.update(new JSONObject().put("policy",permissions).put("authenticated",hasAuthentication()).put("model",model).put("model_network",modelNetwork)); }
        catch(JSONException error) { throw new IllegalArgumentException(error); }
    }
    // Android services execute effects chosen by the shared UI reducer.
    void uiEffect(JSONObject command) {
        try {
            if(command.optString("keyboard").equals("hide")) hideKeyboard();
            switch(command.optString("kind")) {
            case "none": return;
            case "hide_keyboard": hideKeyboard(); return;
            case "exit": finish(); return;
            case "focus": ui.page.focus(command.getString("key")); return;
            case "submit": submit(command.getString("text")); return;
            case "cancel": cancel(); return;
            case "new_session": newSession(); return;
            case "open_session": loadSession(command.getString("id")); return;
            case "load_sessions": hideKeyboard(); loadConversationEntries(); return;
            case "load_worker": {
                long id=command.getLong("id"); File owner=session; WorkerManager manager=workers;
                if(manager!=null) manager.messages(id, rows -> {
                    if (!destroyed && owner.equals(session)) {
                        try { ui.update(new JSONObject().put("worker_owner",id).put("worker_messages",rows)); }
                        catch(JSONException error) { throw new IllegalArgumentException(error); }
                    }
                });
                return;
            }
            case "worker_action": if(workers!=null) workers.action(command.getString("action"),command.getLong("id")); return;
            case "permission": {
                savePermission(command.getString("key"),command.get("allowed"));
                return;
            }
            case "permission_decision": permissionPrompts.resolve(command); return;
            case "save_model_network": {
                String next=command.getString("network");HardwareNetwork.ModelRoute route=new HardwareNetwork.ModelRoute(this,next);
                if(!getPreferences(0).edit().putString("model_network",next).commit()){route.close();throw new IOException("Cannot save model network preference.");}
                HardwareNetwork.ModelRoute old=modelRoute;modelRoute=route;modelNetwork=next;if(old!=null)old.close();updateUiFacts();return;
            }
            case "save_model": {
                String next=command.getString("model");
                if (!getPreferences(0).edit().putString("model",next).commit()) throw new IOException("Cannot save model preference.");
                model=next; updateUiFacts(); updateContext(); return;
            }
            case "copy":
                ((android.content.ClipboardManager)getSystemService(CLIPBOARD_SERVICE))
                    .setPrimaryClip(android.content.ClipData.newPlainText("",command.getString("text"))); return;
            case "read_preview": readPreview(command.getJSONObject("file")); return;
            case "remove_attachment": removeAttachment(command.getInt("index")); return;
            case "resume_main": resumeMain(); return;
            case "compact": begin(() -> { try { compact(); } catch(Exception error) { throw new RuntimeException(error); } }); return;
            case "import_auth": hideKeyboard(); importLogin(); return;
            case "gallery": hideKeyboard(); pickPhoto(); return;
            case "camera": hideKeyboard(); takePhoto(); return;
            case "files": hideKeyboard(); pickFile(); return;
            default: throw new IOException("Unknown platform UI effect.");
            }
        } catch(Exception error) { ui.notice(safe(error)); }
    }
    private void readPreview(JSONObject descriptor) {
        File owner=session;
        worker.execute(() -> {
            try {
                String path=descriptor.getString("path");
                File root=new File(owner,"files").getCanonicalFile();
                File file=new File(root,path.startsWith("/")?path.substring(1):path).getCanonicalFile();
                if(!file.getPath().startsWith(root.getPath()+File.separator) || !file.isFile()) throw new IOException("Preview file is unavailable.");
                byte[] bytes=new byte[16385]; int count;
                try(InputStream in=new FileInputStream(file)) { count=in.read(bytes); }
                if(count<0) count=0;
                int length=Math.min(count,16384);
                for(int i=0;i<length;i++) if(bytes[i]>=0 && bytes[i]<32 && bytes[i]!=9 && bytes[i]!=10 && bytes[i]!=13) throw new IOException("This file contains binary data.");
                JSONObject view=new JSONObject(descriptor.toString()).put("type","file").put("text",new String(bytes,0,length,StandardCharsets.UTF_8)).put("offset",0).put("bytes",length).put("truncated",count>length);
                if(owner.equals(session)) ui.preview(view);
            } catch(Exception error) { ui.notice(safe(error)); }
        });
    }
    private void loadConversationEntries() {
        File owner=session;
        worker.execute(() -> {
            JSONArray rows=new JSONArray();
            try {
                File[] files=new File(getFilesDir(),"workspaces").listFiles(File::isDirectory);
                if(files!=null) {
                    java.util.Arrays.sort(files,(a,b) -> Long.compare(new File(b,"session.json").lastModified(),new File(a,"session.json").lastModified()));
                    for(File dir:files) {
                        if(!dir.getName().matches("[A-Za-z0-9-]{1,80}")) continue;
                        File saved=new File(dir,"session.json"); if(!saved.isFile()) continue;
                        JSONObject summary;
                        try { summary=uiCall(new JSONObject().put("action","summary").put("saved",new JSONObject(read(new FileInputStream(saved),LIMIT)))); }
                        catch(Exception unavailable) { summary=new JSONObject().put("title",dir.getName()).put("preview",""); }
                        summary.put("id",dir.getName()).put("updated",saved.lastModified()).put("current",dir.getName().equals(sessionId));
                        rows.put(summary);
                    }
                }
                if(owner.equals(session)) ui.update(new JSONObject().put("sessions",rows).put("sessions_loading",false).put("sessions_error",""));
            } catch(Exception error) {
                try { ui.update(new JSONObject().put("sessions_loading",false).put("sessions_error",safe(error))); }
                catch(JSONException impossible) { throw new IllegalArgumentException(impossible); }
            }
        });
    }
    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if(hardwareConsent.activityResult(requestCode,resultCode,data))return;
        if (requestCode == 4) {
            String name = getPreferences(0).getString("camera_file", null);
            String owner = getPreferences(0).getString("camera_session", "");
            if (resultCode == RESULT_OK && name != null && owner.equals(sessionId) && !busy) {
                begin(() -> {
                    try {
                        copyPhoto(CameraAttachmentProvider.uri(name), "Camera-" + new java.text.SimpleDateFormat("yyyyMMdd-HHmmss", java.util.Locale.ROOT).format(new java.util.Date()));
                    } catch (Exception error) { throw new RuntimeException(error); }
                    finally { clearCameraCapture(); }
                });
            } else clearCameraCapture();
            return;
        }
        if (requestCode == 3 && resultCode == RESULT_OK && data != null && data.getData() != null) {
            Uri uri = data.getData();
            begin(() -> {try {copyPhoto(uri, attachmentName(uri));}catch(Exception error){throw new RuntimeException(error);}});
            return;
        }
        if (requestCode == 2 && resultCode == RESULT_OK && data != null && data.getData() != null) {
            Uri uri=data.getData();
            begin(() -> {try {copyWorkspaceFile(uri);}catch(Exception error){throw new RuntimeException(error);}});
            return;
        }
        if (requestCode == 1 && resultCode == RESULT_OK && data != null) {
            Uri uri = data.getData();
            if (uri == null)
                return;
            begin(() -> {
                try {
                    String text = read(getContentResolver().openInputStream(uri), 1048576);
                    validateAuth(new JSONObject(text));
                    File dir = new File(getFilesDir(), "credentials");
                    if (!dir.isDirectory() && !dir.mkdirs())
                        throw new IOException("Cannot create credential directory.");
                    atomic(new File(dir, "auth.json"), text);
                    addCard("info", "ChatGPT login imported into private app storage.");
                    updateUiFacts();
                } catch (Exception e) {
                    throw new RuntimeException(e);
                }
            });
        }
    }
    private void onTestIntent(Intent intent) {
        // Development builds only. Files are read exclusively from app-private
        // test/; neither an endpoint override nor arbitrary host paths exist.
        if ((getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0 || intent == null)
            return;
        String name = intent.getStringExtra("test_case");
        if (name == null || !name.matches("[a-zA-Z0-9_-]{1,64}") || busy)
            return;
        // A configuration change must restore UI state, not replay this fixture.
        intent.removeExtra("test_case");
        // Keep only this debug fixture window awake; never change device settings.
        getWindow().addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        ui.restore(CollieUi.object("page","chat"));
        begin(() -> {
            JSONObject report = new JSONObject();
            try {
                File testDir = new File(getFilesDir(), "test");
                JSONObject test = new JSONObject(
                    read(new FileInputStream(new File(testDir, name + ".json")), LIMIT));
                String id = test.optString("session", "android-test");
                boolean existingSession=new File(getFilesDir(),"workspaces/"+id+"/session.json").isFile();
                if(!test.optBoolean("hardware_preserve_handles") || !id.equals(sessionId))loadSession(id);
                // Explicit fixture grants keep transport-focused tests separate
                // from the lazy-permission tests. Existing grants are untouched.
                if (!existingSession && test.has("initial_permissions")) {
                    permissions=loadPermissions(test.get("initial_permissions"));
                    save();updateUiFacts();
                }
                workers.fixtures = test.optJSONObject("worker_responses");
                if (test.optBoolean("hardware_tests")) {
                    Class<?> checks=Class.forName(test.optBoolean("hardware_haptic_tests")?"org.flexscript.collie.HardwareHapticChecks":test.optBoolean("hardware_uwb_gms_tests")?"org.flexscript.collie.HardwareUwbGmsChecks":test.optBoolean("hardware_hce_control_tests")?"org.flexscript.collie.HardwareHceControlChecks":test.optBoolean("hardware_ble_set_tests")?"org.flexscript.collie.HardwareBleSetChecks":test.optBoolean("hardware_accessibility_tests")?"org.flexscript.collie.HardwareAccessibilityChecks":test.optBoolean("hardware_screen_tests")?"org.flexscript.collie.HardwareScreenChecks":test.optBoolean("hardware_hce_tests")?"org.flexscript.collie.HardwareHceChecks":test.optBoolean("hardware_camera_tests")?"org.flexscript.collie.HardwareCameraChecks":test.optBoolean("hardware_document_tests")?"org.flexscript.collie.HardwareDocumentChecks":test.optBoolean("hardware_uwb_tests")?"org.flexscript.collie.HardwareUwbChecks":test.optBoolean("hardware_biometric_tests")?"org.flexscript.collie.HardwareBiometricChecks":test.optBoolean("hardware_input_tests")?"org.flexscript.collie.HardwareInputChecks":"org.flexscript.collie.HardwareNetworkChecks");
                    JSONObject result=(JSONObject)checks.getMethod(test.optBoolean("hardware_hce_control_restore_tests")?"runRestore":test.optBoolean("hardware_hce_control_recovered_tests")?"runRecovered":test.optBoolean("hardware_hce_control_orphan_tests")?"runOrphan":test.optBoolean("hardware_ble_hidden_tests")?"runHidden":test.optBoolean("hardware_ble_startup_deadline_tests")?"runStartupDeadline":test.optBoolean("hardware_ble_request_deadline_tests")?"runRequestDeadline":test.optBoolean("hardware_screen_background_tests")?"runBackground":test.optBoolean("hardware_screen_frame_tests")?"runFrame":test.optBoolean("hardware_screen_video_tests")?"runVideo":test.optBoolean("hardware_hce_background_tests")?"runBackground":test.optBoolean("hardware_hce_orphan_tests")?"runOrphan":test.optBoolean("hardware_hce_recovered_tests")?"runRecovered":test.optBoolean("hardware_camera_yuv_tests")?"runYuv":test.optBoolean("hardware_camera_lifecycle_tests")?"runLifecycle":test.optBoolean("hardware_camera_physical_tests")?"runPhysical":test.optBoolean("hardware_camera_manual_tests")?"runManual":test.optBoolean("hardware_camera_video_tests")?"runVideo":test.optBoolean("hardware_document_read_grant_tests")?"runReadGrant":test.optBoolean("hardware_document_live_tests")?"runLive":test.optBoolean("hardware_document_revoke_tests")?"runRevoke":test.optBoolean("hardware_uwb_lifecycle_tests")?"runLifecycle":test.optBoolean("hardware_biometric_late_tests")?"runLate":test.optBoolean("hardware_biometric_live_tests")?"runLive":test.optBoolean("hardware_nfc_tests")?"runNfc":test.optBoolean("hardware_bluetooth_tests")?"runBluetooth":test.optBoolean("hardware_aware_tests")?"runAware":test.optBoolean("hardware_revocation_tests")?"runRevocation":test.optBoolean("hardware_wifi_tests")?"runWifi":test.optBoolean("hardware_wifi_request_tests")?"runWifiRequest":test.optBoolean("hardware_wifi_recovery_tests")?"runWifiRecovery":test.optBoolean("hardware_cellular_tests")?"runCellular":test.optBoolean("hardware_microphone_tests")?"runMicrophone":test.optBoolean("hardware_vpn_tests")?"runVpn":"run",MainActivity.class,File.class).invoke(null,this,session);
                    report.put("hardware",result);if(!result.optBoolean("ok"))throw new IOException(result.toString());
                } else if (test.has("ui_packets")) {
                    java.util.concurrent.CountDownLatch ready = new java.util.concurrent.CountDownLatch(1);
                    runOnUiThread(() -> {
                        try {
                            Class<?> checks = Class.forName("org.flexscript.collie.UiRendererChecks");
                            JSONObject result = (JSONObject)checks.getMethod("run", Activity.class,
                                android.view.ViewGroup.class, JSONArray.class)
                                .invoke(null, this, navigation, test.getJSONArray("ui_packets"));
                            report.put("ui", result);
                        } catch (Exception error) {
                            try { report.put("ui", new JSONObject().put("ok", false).put("error", (error.getCause() == null ? error : error.getCause()).toString())); }
                            catch (Exception ignored) {}
                        } finally { ready.countDown(); }
                    });
                    if (!ready.await(20, java.util.concurrent.TimeUnit.SECONDS)) throw new IOException("UI checks timed out.");
                    if (!report.getJSONObject("ui").optBoolean("ok")) throw new IOException(report.getJSONObject("ui").toString());
                } else if (test.optBoolean("resume_pending")) {
                    continueTurn(test.optJSONArray("responses"));
                } else if (test.optBoolean("resume_only")) {
                    // Restore an existing conversation for UI/lifecycle verification.
                } else if (test.has("source")) {
                    if (test.optBoolean("cancel_before_run"))
                        nativeCancel();
                    JSONObject r = engine(
                        3, new JSONObject()
                               .put("config", config())
                               .put("source", test.getString("source"))
                               .put("_cancel_before_run", test.optBoolean("cancel_before_run"))
                               .put("history", archive));
                    addCard("source", test.getString("source"));
                    addResult(r);
                    report.put("observation", r);
                } else
                    turn(test.getString("prompt"), test.optJSONArray("responses"));
                report.put("ok", true).put("messages", messages).put("session", sessionId);
                try {
                    report.put("workers", workers.data("list", 0).getJSONArray("workers"));
                } catch (Exception ignored) {
                }
            } catch (Exception e) {
                try {
                    report.put("ok", false).put("error", safe(e));
                } catch (Exception ignored) {
                }
                showError(safe(e));
            } finally {
                try {
                    File dir = new File(getFilesDir(), "test");
                    dir.mkdirs();
                    atomic(new File(dir, name + ".result.json"), report.toString());
                } catch (Exception e) {
                    showError("Cannot save test result.");
                }
            }
        });
    }
    @Override
    public void onRequestPermissionsResult(int requestCode,String[] requested,int[] results) {
        super.onRequestPermissionsResult(requestCode,requested,results);
        if(requestCode==57){
            String owner=getPreferences(0).getString("manual_camera_session","");getPreferences(0).edit().remove("manual_camera_session").commit();
            if(!destroyed&&owner.equals(sessionId)){
                if(checkSelfPermission(android.Manifest.permission.CAMERA)==android.content.pm.PackageManager.PERMISSION_GRANTED)takePhotoGranted();
                else ui.notice("Camera permission was not granted.");
            }return;
        }
        hardwareConsent.result(requestCode,requested,results);
    }
    @Override
    protected void onDestroy() {
        destroyed = true;
        hardwareConsent.close();
        if (activeTask != null)
            activeTask.close();
        stopped = true;
        nativeCancel();
        VmInternet.cancel();VmHardware.cancel();VmHardware.closeWorkspace(null);
        if(modelRoute!=null)modelRoute.close();
        HttpsURLConnection c = connection;
        if (c != null)
            c.disconnect();
        if (workers != null)
            workers.close();
        worker.shutdown();
        super.onDestroy();
    }
}
