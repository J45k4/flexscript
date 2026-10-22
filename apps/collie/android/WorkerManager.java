package org.flexscript.collie;

import java.io.*;
import java.util.concurrent.*;
import org.json.*;

/**
 * Android thread/lifecycle adapter. Flexscript chooses which jobs to start,
 * cancel or recover, and owns every worker conversation and its persistence.
 */
final class WorkerManager implements AutoCloseable {
    final MainActivity host;
    final File root;
    private final ScheduledExecutorService timer = Executors.newSingleThreadScheduledExecutor();
    private final ExecutorService threads = Executors.newCachedThreadPool();
    private final ConcurrentHashMap<Long, PlatformTask> running = new ConcurrentHashMap<>();
    private final Runnable changed;
    private volatile boolean closed;
    private boolean recovered;
    private volatile JSONArray workers = new JSONArray();
    private volatile String problem = "";
    volatile JSONObject fixtures;
    WorkerManager(MainActivity host, File root, Runnable changed) {
        this.host = host;
        this.root = root;
        this.changed = changed;
        timer.scheduleWithFixedDelay(this::scan, 800, 800, TimeUnit.MILLISECONDS);
    }
    JSONObject data(String action, long id) throws Exception {
        return data(new JSONObject().put("action", action).put("id", id));
    }
    JSONObject data(JSONObject request) throws Exception {
        if (closed)
            throw new IOException("Worker environment closed.");
        return host.engineAt(root, 9, request.put("config", host.workerConfig(root, 0)));
    }
    JSONArray snapshot() {
        try {
            return new JSONArray(workers.toString());
        } catch (JSONException e) {
            return new JSONArray();
        }
    }
    String problem() { return problem; }
    private void scan() {
        if (closed)
            return;
        try {
            JSONArray active = new JSONArray();
            for (Long id : running.keySet())
                active.put(id);
            JSONObject plan =
                data(new JSONObject()
                         .put("action", "plan")
                         .put("active", active)
                         .put("recover", !recovered)
                         .put("allowed", host.workersAllowed())
                         .put("authenticated", fixtures != null || host.hasAuthentication()));
            recovered = true;
            workers = plan.getJSONArray("workers");
            problem = "";
            JSONArray cancel = plan.getJSONArray("cancel");
            for (int i = 0; i < cancel.length(); i++) {
                PlatformTask task = running.get(cancel.getLong(i));
                if (task != null)
                    task.cancel();
            }
            JSONArray start = plan.getJSONArray("start");
            for (int i = 0; i < start.length(); i++) {
                JSONObject entry = start.getJSONObject(i);
                long id = entry.getLong("id");
                PlatformTask task = new PlatformTask(host, root, id, null);
                running.put(id, task);
                JSONArray fixture =
                    fixtures == null ? null : fixtures.optJSONArray(Long.toString(id));
                final JSONArray replies =
                    fixtures != null && fixture == null ? new JSONArray() : fixture;
                threads.execute(() -> {
                    try {
                        task.run("open_worker", new JSONObject(), entry, replies,
                                 (state, cards) -> changed.run());
                    } catch (Exception error) {
                        if (!closed)
                            problem = MainActivity.safe(error);
                    } finally {
                        running.remove(id, task);
                        changed.run();
                    }
                });
            }
            changed.run();
        } catch (Exception error) {
            if (!closed) {
                problem = MainActivity.safe(error);
                changed.run();
            }
        }
    }
    void action(String action, long id) {
        if (closed)
            return;
        timer.execute(() -> {
            try {
                data(action, id);
                scan();
            } catch (Exception e) {
                problem = MainActivity.safe(e);
                changed.run();
            }
        });
    }
    void messages(long id, java.util.function.Consumer<JSONArray> done) {
        if (closed)
            return;
        timer.execute(() -> {
            JSONArray rows = new JSONArray();
            try {
                rows = data("messages", id).getJSONArray("messages");
            } catch (Exception e) {
                problem = MainActivity.safe(e);
            }
            done.accept(rows);
        });
    }
    public void close() {
        closed = true;
        for (PlatformTask task : running.values())
            task.close();
        timer.shutdownNow();
        threads.shutdown();
    }
}
