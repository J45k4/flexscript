package org.flexscript.collie;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.graphics.Color;
import android.graphics.Typeface;
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
    }
    private static native long nativeCall(
        long op, ByteBuffer input, long size, ByteBuffer output, ByteBuffer session);
    private static native void nativeCancel();
    private static native void nativeBegin();
    // Called synchronously by the trusted native broker, never by raw guest FFI.
    private static byte[] vmHttpGet(byte[] url) { return VmInternet.get(url); }
    private static final Object ENGINE = new Object();
    private static final int LIMIT = 8 * 1024 * 1024;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private volatile boolean stopped, busy, destroyed;
    private volatile HttpsURLConnection connection;
    private LinearLayout transcript;
    private ScrollView scroll;
    private EditText prompt;
    private TextView status;
    private CollieUi ui;
    private FrameLayout navigation;
    private ConversationsPage conversations;
    private PermissionsPage permissionsPage;
    private volatile JSONObject permissions = AgentPermissions.load(null);
    private android.window.OnBackInvokedCallback conversationsBack;
    private android.window.OnBackInvokedCallback permissionsBack;
    private String model = "gpt-6.1-sol", sessionId;
    private File session;
    private JSONArray messages = new JSONArray(), archive = new JSONArray(),
                      cards = new JSONArray();
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
        byte[] input = request.toString().getBytes(StandardCharsets.UTF_8);
        ByteBuffer out = ByteBuffer.allocateDirect(LIMIT);
        long n;
        synchronized (ENGINE) {
            n = nativeCall(op, buffer(input, true), input.length, out,
                buffer(session.getAbsolutePath().getBytes(StandardCharsets.UTF_8), true));
        }
        if (n < 0 || n > LIMIT)
            throw new IOException("Native engine failed (" + n + ").");
        byte[] bytes = new byte[(int) n];
        out.get(bytes);
        JSONObject result = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
        if (result.has("error"))
            throw new IOException(result.getString("error"));
        return result;
    }
    private JSONObject config() throws JSONException {
        return new JSONObject()
            .put("model", model)
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
        ui = new CollieUi(this,
            ()
                -> {
                if (busy)
                    cancel();
                else
                    submit();
            },
            ()
                -> {
                if (!busy)
                    newSession();
            },
            this::showConversations, this::menu,
            new File(getFilesDir(), "credentials/auth.json").isFile());
        transcript = ui.transcript;
        scroll = ui.scroll;
        prompt = ui.prompt;
        status = ui.status;
        navigation = new FrameLayout(this);
        navigation.addView(ui.page, new FrameLayout.LayoutParams(-1, -1));
        setContentView(navigation);
        model = getPreferences(0).getString("model", "gpt-6.1-sol");
        try {
            String id = getPreferences(0).getString("session", null);
            if (id == null)
                newSession();
            else
                loadSession(id);
        } catch (Exception e) {
            newSession();
            showError("Previous session could not be loaded: " + safe(e));
        }
        if (state != null && state.getBoolean("permissions_visible")) {
            showPermissions();
        } else if (state != null && state.getBoolean("conversations_visible")) {
            showConversations();
            if (conversations != null)
                conversations.query(state.getString("conversations_query", ""));
        }
        onTestIntent(getIntent());
    }
    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        onTestIntent(intent);
    }
    private void prepareSession(String id) throws IOException {
        if (!id.matches("[A-Za-z0-9-]{1,80}"))
            throw new IOException("Invalid session ID.");
        sessionId = id;
        session = new File(getFilesDir(), "workspaces/" + id);
        if (!new File(session, "files").isDirectory() && !new File(session, "files").mkdirs())
            throw new IOException("Cannot create workspace.");
        getPreferences(0).edit().putString("session", id).apply();
    }
    private void newSession() {
        if (busy)
            return;
        try {
            prepareSession(UUID.randomUUID().toString());
            permissions = AgentPermissions.load(null);
            messages = new JSONArray();
            archive = new JSONArray();
            cards = new JSONArray();
            usage = null;
            anchor = 0;
            ui.clear();
            save();
            addCard("info",
                "App-private workspace ready. Import ChatGPT auth.json from Menu to connect.");
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
            permissions = AgentPermissions.load(saved.optJSONObject("permissions"));
            messages = saved.getJSONArray("messages");
            archive = saved.optJSONArray("archive");
            if (archive == null)
                archive = new JSONArray();
            cards = saved.optJSONArray("cards");
            if (cards == null)
                cards = new JSONArray();
            usage = saved.optJSONObject("usage");
            anchor = saved.optInt("anchor", 0);
        } else {
            permissions = AgentPermissions.load(null);
            messages = new JSONArray();
            archive = new JSONArray();
            cards = new JSONArray();
            usage = null;
            anchor = 0;
        }
        final JSONArray visible = new JSONArray(cards.toString());
        runOnUiThread(() -> {
            ui.clear();
            try {
                for (int i = 0; i < visible.length(); i++) renderCard(visible.getJSONObject(i));
            } catch (JSONException e) {
                showError(safe(e));
            }
        });
        updateContext();
    }
    private void save() throws Exception {
        JSONObject data = new JSONObject()
                              .put("messages", messages)
                              .put("archive", archive)
                              .put("cards", cards)
                              .put("permissions", permissions)
                              .put("anchor", anchor);
        if (usage != null)
            data.put("usage", usage);
        atomic(new File(session, "session.json"), data.toString());
    }
    private static void atomic(File file, String text) throws IOException {
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
    private static String read(InputStream in, int limit) throws IOException {
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
        runOnUiThread(() -> ui.setWorking(value));
    }
    private void cancel() {
        stopped = true;
        nativeCancel();
        VmInternet.cancel();
        HttpsURLConnection c = connection;
        if (c != null)
            c.disconnect();
        status.setText("Stopping…");
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
                working(false);
                updateContext();
            }
        });
    }
    private void submit() {
        String text = prompt.getText().toString().trim();
        if (text.isEmpty())
            return;
        prompt.setText("");
        begin(() -> {
            try {
                turn(text, null);
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        });
    }
    private JSONObject authentication() throws Exception {
        File f = new File(getFilesDir(), "credentials/auth.json");
        if (!f.isFile())
            throw new IOException("Import ChatGPT auth.json from Menu first.");
        JSONObject auth = new JSONObject(read(new FileInputStream(f), 1048576));
        validateAuth(auth);
        return auth.getJSONObject("tokens");
    }
    private static void validateAuth(JSONObject auth) throws Exception {
        String mode = auth.optString("auth_mode", "");
        JSONObject tokens = auth.optJSONObject("tokens");
        if ((!mode.isEmpty() && !mode.equals("null") && !mode.equals("chatgpt")) || tokens == null
            || tokens.optString("access_token").isEmpty()
            || tokens.optString("account_id").isEmpty())
            throw new IOException("Expected ChatGPT Codex auth.json with access_token and "
                + "account_id; API keys are unsupported.");
        for (String key : new String[] {"access_token", "account_id"}) {
            String s = tokens.getString(key);
            if (s.length() > 32768 || s.indexOf('\r') >= 0 || s.indexOf('\n') >= 0)
                throw new IOException("Invalid authentication field.");
        }
    }
    private static String safe(Throwable e) {
        while (e.getCause() != null) e = e.getCause();
        String text = e.getMessage();
        return text == null ? e.getClass().getSimpleName() : text;
    }
    private JSONObject response(JSONObject body, boolean compact, JSONArray fixture, int index)
        throws Exception {
        checkStop();
        if (fixture != null) {
            if (index >= fixture.length())
                throw new IOException("Fixture ran out of responses.");
            return engine(compact ? 5 : 2, request().put("event", fixture.getJSONObject(index)));
        }
        JSONObject tokens = authentication();
        HttpsURLConnection c =
            (HttpsURLConnection) new URL("https://chatgpt.com/backend-api/codex/responses")
                .openConnection();
        connection = c;
        c.setInstanceFollowRedirects(false);
        c.setConnectTimeout(30000);
        c.setReadTimeout(120000);
        c.setRequestMethod("POST");
        c.setDoOutput(true);
        c.setRequestProperty("Authorization", "Bearer " + tokens.getString("access_token"));
        c.setRequestProperty("ChatGPT-Account-ID", tokens.getString("account_id"));
        c.setRequestProperty("originator", "collie");
        c.setRequestProperty("User-Agent", "collie/0.1");
        c.setRequestProperty("Content-Type", "application/json");
        c.setRequestProperty("Accept", "text/event-stream");
        c.setRequestProperty("Accept-Encoding", "identity");
        byte[] data = body.toString().getBytes(StandardCharsets.UTF_8);
        c.setFixedLengthStreamingMode(data.length);
        try {
            checkStop();
            try (OutputStream out = c.getOutputStream()) {
                out.write(data);
            }
            int statusCode = c.getResponseCode();
            if (statusCode != 200) {
                if (statusCode == 401)
                    throw new IOException(
                        "ChatGPT login expired. Refresh auth.json with Codex and import it again.");
                if (statusCode == 429)
                    throw new IOException("Codex usage limit reached. Retry later.");
                throw new IOException("Codex HTTP " + statusCode + ".");
            }
            String type = c.getContentType();
            if (type != null
                && !type.toLowerCase(java.util.Locale.ROOT).startsWith("text/event-stream"))
                throw new IOException("Unexpected Codex response type.");
            try (InputStream in = c.getInputStream()) {
                ByteArrayOutputStream line = new ByteArrayOutputStream();
                StringBuilder event = new StringBuilder(), prose = new StringBuilder(),
                              source = new StringBuilder();
                String key = "";
                int total = 0;
                TextView preview = null;
                if (!compact) {
                    java.util.concurrent.FutureTask<TextView> task =
                        new java.util.concurrent.FutureTask<>(() -> { return ui.beginStream(); });
                    runOnUiThread(task);
                    preview = task.get();
                }
                for (;;) {
                    checkStop();
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
                        if (json.equals("[DONE]"))
                            continue;
                        JSONObject e = new JSONObject(json);
                        String kind = e.optString("type");
                        if (!compact && kind.equals("response.output_text.delta")) {
                            prose.append(e.getString("delta"));
                            if (prose.length() > 65536)
                                throw new IOException("Assistant text exceeds limit.");
                            String p = prose.toString();
                            final TextView v = preview;
                            runOnUiThread(() -> { ui.stream(v, p); });
                        } else if (!compact && kind.equals("response.output_item.added")) {
                            JSONObject item = e.getJSONObject("item");
                            if (item.optString("type").equals("custom_tool_call")) {
                                if (!item.optString("name").equals("flexscript") || !key.isEmpty())
                                    throw new IOException("Unexpected or multiple tool calls.");
                                key = item.optString("id", item.optString("call_id"));
                            }
                        } else if (!compact
                            && kind.equals("response.custom_tool_call_input.delta")) {
                            String id = e.optString("item_id", e.optString("call_id"));
                            if (id.isEmpty() || (!key.isEmpty() && !key.equals(id)))
                                throw new IOException("Tool stream identity changed.");
                            key = id;
                            source.append(e.getString("delta"));
                            if (source.length() > 65536)
                                throw new IOException("Tool input exceeds limit.");
                        } else if (kind.equals("response.completed")) {
                            final TextView v = preview;
                            if (v != null)
                                runOnUiThread(() -> ui.removeStream());
                            JSONObject req = request()
                                                 .put("event", e)
                                                 .put("streamed_text", prose.toString())
                                                 .put("streamed_source", source.toString())
                                                 .put("tool_item_id", key);
                            return engine(compact ? 5 : 2, req);
                        } else if (kind.equals("response.failed")
                            || kind.equals("response.incomplete") || kind.equals("error"))
                            throw new IOException("Model response failed or was incomplete.");
                    }
                }
            }
        } finally {
            connection = null;
            c.disconnect();
        }
    }
    private JSONObject limits() throws Exception {
        JSONObject r = request().put("anchor", anchor);
        if (usage != null)
            r.put("usage", usage);
        return engine(6, r);
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
    private void compact() throws Exception {
        checkStop();
        JSONObject result = response(engine(4, request()), true, null, 0);
        messages = result.getJSONArray("messages");
        usage = null;
        anchor = 0;
        save();
        addCard("info", "Context compacted. FlexDB and workspace files are unchanged.");
    }
    private void turn(String user, JSONArray fixture) throws Exception {
        if (fixture == null)
            authentication();
        JSONObject item = new JSONObject().put("role", "user").put("content", user);
        messages.put(item);
        archive.put(item);
        addCard("user", user);
        save();
        if (fixture == null) {
            JSONObject l = limits();
            if (l.getJSONObject("usage").optLong("total_tokens")
                >= l.getLong("auto_compact_token_limit"))
                compact();
        }
        for (int step = 0; step < 16; step++) {
            checkStop();
            runOnUiThread(() -> status.setText("Thinking…"));
            JSONObject reply = response(engine(1, request()), false, fixture, step);
            JSONArray items = reply.getJSONArray("items");
            JSONObject call = reply.optJSONObject("tool_call");
            String prose = reply.optString("message");
            if (!prose.isEmpty())
                addCard("assistant", prose);
            if (call == null) {
                for (int i = 0; i < items.length(); i++) {
                    messages.put(items.get(i));
                    archiveItem(items.getJSONObject(i));
                }
                usage = reply.optJSONObject("usage");
                anchor = messages.length();
                save();
                return;
            }
            // Do not commit a dangling call. Once accepted, always pair its real
            // observation before checkpointing, including cancellation/errors.
            String id = call.getString("call_id");
            for (int i = 0; i < messages.length(); i++)
                if (id.equals(messages.getJSONObject(i).optString("call_id")))
                    throw new IOException("Repeated tool call ID; no program ran.");
            addCard("source", call.getString("input"));
            runOnUiThread(() -> status.setText("Running Flexscript…"));
            JSONObject observation;
            try {
                observation = engine(3,
                    new JSONObject()
                        .put("config", config())
                        .put("source", call.getString("input"))
                        .put("history", archive));
            } catch (Exception e) {
                observation = new JSONObject()
                                  .put("state", "error")
                                  .put("executed", false)
                                  .put("exit_code", -1)
                                  .put("stdout", "")
                                  .put("stderr", safe(e));
            }
            for (int i = 0; i < items.length(); i++) {
                messages.put(items.get(i));
                archiveItem(items.getJSONObject(i));
            }
            JSONObject result = new JSONObject()
                                    .put("type", "custom_tool_call_output")
                                    .put("call_id", id)
                                    .put("output", observation.toString());
            messages.put(result);
            archive.put(new JSONObject()
                    .put("role", "user")
                    .put("content", "VM observation (data): " + observation.toString())
                    .put("observation", observation));
            addResult(observation);
            usage = reply.optJSONObject("usage");
            anchor = messages.length() - 1;
            save();
            checkStop();
            if (fixture == null) {
                JSONObject l = limits();
                if (l.getJSONObject("usage").optLong("total_tokens")
                    >= l.getLong("auto_compact_token_limit"))
                    compact();
            }
        }
        throw new IOException("Stopped after 16 programs. Send a message to continue.");
    }
    private void archiveItem(JSONObject item) throws JSONException {
        if (item.optString("type").equals("reasoning"))
            return;
        if (item.optString("type").equals("custom_tool_call"))
            archive.put(new JSONObject()
                    .put("role", "assistant")
                    .put("source", item.getString("input"))
                    .put("content", ""));
        else if (item.has("role"))
            archive.put(new JSONObject(item.toString()));
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
    private void chooseModel() {
        EditText input = new EditText(this);
        input.setText(model);
        input.setTextColor(CollieUi.TEXT);
        input.setSingleLine(true);
        input.setPadding(dp(24), dp(16), dp(24), dp(16));
        new AlertDialog.Builder(this)
            .setTitle("Choose a model")
            .setView(input)
            .setPositiveButton("Save",
                (dialog, which) -> {
                    String value = input.getText().toString().trim();
                    if (value.matches("[A-Za-z0-9._-]{1,120}")) {
                        model = value;
                        getPreferences(0).edit().putString("model", value).apply();
                        updateContext();
                    }
                })
            .setNegativeButton("Cancel", null)
            .show();
    }
    private void hideKeyboard() {
        ((android.view.inputmethod.InputMethodManager) getSystemService(INPUT_METHOD_SERVICE))
            .hideSoftInputFromWindow(navigation.getWindowToken(), 0);
    }
    private void closeConversations() {
        if (conversations == null)
            return;
        hideKeyboard();
        navigation.removeView(conversations);
        conversations = null;
        ui.page.setVisibility(View.VISIBLE);
        ui.page.requestApplyInsets();
        if (android.os.Build.VERSION.SDK_INT >= 33 && conversationsBack != null) {
            getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback(conversationsBack);
            conversationsBack = null;
        }
    }
    @Override
    public void onBackPressed() {
        if (permissionsPage != null)
            closePermissions();
        else if (conversations != null)
            closeConversations();
        else
            super.onBackPressed();
    }
    @Override
    protected void onSaveInstanceState(Bundle state) {
        super.onSaveInstanceState(state);
        state.putBoolean("conversations_visible", conversations != null);
        state.putBoolean("permissions_visible", permissionsPage != null);
        if (conversations != null)
            state.putString("conversations_query", conversations.query());
    }
    private void showConversations() {
        if (busy) {
            new AlertDialog.Builder(this)
                .setMessage("Stop the current reply to browse conversations.")
                .setPositiveButton("Got it", null)
                .show();
            return;
        }
        if (conversations != null)
            return;
        hideKeyboard();
        ConversationsPage page = new ConversationsPage(this, ui, this::closeConversations,
            ()
                -> {
                newSession();
                closeConversations();
            },
            id -> {
                try {
                    if (!id.equals(sessionId))
                        loadSession(id);
                    closeConversations();
                } catch (Exception error) {
                    new AlertDialog.Builder(this)
                        .setMessage("Couldn’t open this conversation: " + safe(error))
                        .setPositiveButton("OK", null)
                        .show();
                }
            });
        conversations = page;
        ui.page.setVisibility(View.GONE);
        navigation.addView(page, new FrameLayout.LayoutParams(-1, -1));
        page.requestApplyInsets();
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            conversationsBack = this::closeConversations;
            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, conversationsBack);
        }
        final String current = sessionId;
        worker.execute(() -> {
            try {
                File[] files = new File(getFilesDir(), "workspaces").listFiles(File::isDirectory);
                java.util.ArrayList<ConversationsPage.Entry> entries = new java.util.ArrayList<>();
                if (files != null) {
                    java.util.Arrays.sort(files,
                        (a, b)
                            -> Long.compare(new File(b, "session.json").lastModified(),
                                new File(a, "session.json").lastModified()));
                    for (File dir : files) {
                        if (!dir.getName().matches("[A-Za-z0-9-]{1,80}"))
                            continue;
                        File saved = new File(dir, "session.json");
                        if (!saved.isFile())
                            continue;
                        String title = "New conversation",
                               preview = "Start a conversation in this workspace.";
                        try {
                            JSONArray history =
                                new JSONObject(read(new FileInputStream(saved), LIMIT))
                                    .getJSONArray("messages");
                            boolean titled = false;
                            for (int n = 0; n < history.length(); n++) {
                                JSONObject item = history.getJSONObject(n);
                                String role = item.optString("role"),
                                       text = item.optString("content");
                                if (!(role.equals("user") || role.equals("assistant"))
                                    || text.trim().isEmpty())
                                    continue;
                                if (!titled && role.equals("user")) {
                                    title = text.replace('\n', ' ');
                                    titled = true;
                                }
                                preview = MessageStyle.markdown(text).toString().replace('\n', ' ');
                            }
                        } catch (Exception unreadable) {
                            title = "Saved conversation";
                            preview = "Couldn’t read the saved messages.";
                        }
                        if (title.length() > 256)
                            title = title.substring(0, 253) + "…";
                        if (preview.length() > 180)
                            preview = preview.substring(0, 177) + "…";
                        entries.add(new ConversationsPage.Entry(dir.getName(), title, preview,
                            saved.lastModified(), dir.getName().equals(current)));
                    }
                }
                runOnUiThread(() -> {
                    if (conversations == page && !destroyed)
                        page.entries(entries);
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    if (conversations == page && !destroyed)
                        page.failed();
                });
            }
        });
    }
    private void closePermissions() {
        if (permissionsPage == null) return;
        navigation.removeView(permissionsPage);
        permissionsPage = null;
        ui.page.setVisibility(View.VISIBLE);
        ui.page.requestApplyInsets();
        if (android.os.Build.VERSION.SDK_INT >= 33 && permissionsBack != null) {
            getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback(permissionsBack);
            permissionsBack = null;
        }
    }
    private void showPermissions() {
        if (busy || permissionsPage != null) return;
        closeConversations();
        hideKeyboard();
        permissionsPage = new PermissionsPage(this, ui, permissions, this::closePermissions,
            (key, allowed) -> {
                JSONObject previous = permissions;
                try {
                    JSONObject next = new JSONObject(previous.toString());
                    next.put(key, allowed);
                    permissions = next;
                    save();
                    return true;
                } catch (Exception error) {
                    permissions = previous;
                    Toast.makeText(this, "Couldn’t save permissions: " + safe(error), Toast.LENGTH_LONG).show();
                    return false;
                }
            });
        ui.page.setVisibility(View.GONE);
        navigation.addView(permissionsPage, new FrameLayout.LayoutParams(-1, -1));
        permissionsPage.requestApplyInsets();
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            permissionsBack = this::closePermissions;
            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, permissionsBack);
        }
    }
    private void menu() {
        if (busy) {
            new AlertDialog.Builder(this)
                .setMessage("Stop the current reply to change conversations or settings.")
                .setPositiveButton("Got it", null)
                .show();
            return;
        }
        boolean connected = new File(getFilesDir(), "credentials/auth.json").isFile();
        ui.sheet("Your workspace",
            connected ? "ChatGPT login saved · " + model
                      : "Connect ChatGPT to start a conversation.",
            new String[] {"New conversation", "Conversations", "Permissions", "Model · " + model,
                "Compact context", connected ? "Update ChatGPT login" : "Connect ChatGPT"},
            new Runnable[] {this::newSession, this::showConversations, this::showPermissions, this::chooseModel,
                ()
                    -> begin(() -> {
                    try {
                        compact();
                    } catch (Exception e) {
                        throw new RuntimeException(e);
                    }
                }),
                this::importLogin});
    }
    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
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
        closeConversations();
        closePermissions();
        begin(() -> {
            JSONObject report = new JSONObject();
            try {
                File testDir = new File(getFilesDir(), "test");
                JSONObject test = new JSONObject(
                    read(new FileInputStream(new File(testDir, name + ".json")), LIMIT));
                String id = test.optString("session", "android-test");
                loadSession(id);
                if (test.optBoolean("resume_only")) {
                    // Restore an existing conversation for UI/lifecycle verification.
                } else if (test.has("source")) {
                    if (test.optBoolean("cancel_before_run"))
                        nativeCancel();
                    JSONObject r = engine(3,
                        new JSONObject()
                            .put("config", config())
                            .put("source", test.getString("source"))
                            .put("history", archive));
                    addCard("source", test.getString("source"));
                    addResult(r);
                    report.put("observation", r);
                } else
                    turn(test.getString("prompt"), test.optJSONArray("responses"));
                report.put("ok", true).put("messages", messages).put("session", sessionId);
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
    protected void onDestroy() {
        destroyed = true;
        stopped = true;
        nativeCancel();
        VmInternet.cancel();
        HttpsURLConnection c = connection;
        if (c != null)
            c.disconnect();
        worker.shutdown();
        super.onDestroy();
    }
}
