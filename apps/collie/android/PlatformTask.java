package org.flexscript.collie;

import java.io.*;
import java.net.HttpURLConnection;
import org.json.*;

/**
 * Executes platform effects requested by the shared Flexscript conversation
 * machine. No scheduling, tool/history mutation, compaction or resume policy.
 */
final class PlatformTask implements AutoCloseable {
    interface Check {
        void run() throws Exception;
    }
    interface Update {
        void apply(JSONObject state, JSONArray cards) throws Exception;
    }
    final MainActivity host;
    final File root;
    final long id;
    private final Check owner;
    volatile boolean closed, cancelled;
    volatile HttpURLConnection connection;
    PlatformTask(MainActivity host, File root, long id, Check owner) {
        this.host = host;
        this.root = root;
        this.id = id;
        this.owner = owner;
    }
    void check() throws Exception {
        if (closed || cancelled || Thread.currentThread().isInterrupted())
            throw new IOException("Cancelled.");
        if (owner != null)
            owner.run();
    }
    void cancel() {
        cancelled = true;
        HttpURLConnection c = connection;
        if (c != null)
            c.disconnect();
    }
    public void close() {
        closed = true;
        cancel();
    }
    void run(String action, JSONObject state, JSONObject input, JSONArray fixture, Update update)
        throws Exception {
        JSONObject event = input;
        for (;;) {
            JSONObject config = host.workerConfig(root, id);
            JSONObject request = new JSONObject()
                                     .put("config", config)
                                     .put("state", state)
                                     .put("action", action)
                                     .put("fixture", fixture != null);
            if (event != null)
                for (java.util.Iterator<String> keys = event.keys(); keys.hasNext();) {
                    String key = keys.next();
                    request.put(key, event.get(key));
                }
            JSONObject transition = host.engineAt(root, 8, request);
            state = transition.getJSONObject("state");
            if (update != null)
                update.apply(state, transition.getJSONArray("cards"));
            JSONObject command = transition.getJSONObject("command");
            if (action.equals("failure") && cancelled)
                return;
            if (command.getString("kind").equals("done")) {
                if (command.has("error"))
                    throw new IOException(command.getString("error"));
                return;
            }
            try {
                check();
                event = new JSONObject();
                switch (command.getString("kind")) {
                case "model": {
                    JSONObject base = new JSONObject()
                                          .put("config", config)
                                          .put("messages", state.getJSONArray("messages"));
                    boolean compact = command.getBoolean("compact");
                    JSONObject reply = host.responseAt(
                        host.engineAt(root, command.getInt("engine_op"), base), compact, fixture,
                        command.getInt("step"), root, base, id == 0 ? null : this);
                    event.put("reply", reply);
                    action = compact ? "compacted" : "reply";
                    break;
                }
                case "vm": {
                    JSONObject vm = command.getJSONObject("request")
                                        .put("config", config)
                                        .put("history", state.getJSONArray("archive"));
                    event.put("observation", host.engineAt(root, 3, vm));
                    action = "observation";
                    break;
                }
                case "wait":
                    if (id == 0)
                        host.waitingFor(command.getLong("waiting_for"));
                    Thread.sleep(command.getInt("milliseconds"));
                    action = "next";
                    break;
                default:
                    throw new IOException("Unknown platform effect.");
                }
            } catch (Exception error) {
                if (closed || host.platformClosed())
                    throw error;
                action = "failure";
                event = new JSONObject()
                            .put("error", MainActivity.safe(error))
                            .put("cancelled", cancelled);
            }
        }
    }
}
