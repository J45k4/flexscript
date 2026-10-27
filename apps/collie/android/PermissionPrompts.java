package org.flexscript.collie;

import java.io.IOException;
import java.util.ArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.json.*;

/** Lifecycle/queue adapter only. Flexscript supplies the prompt and owns grants. */
final class PermissionPrompts {
    private final MainActivity host;
    // Accessed only on Android's UI thread. Waiting never holds the VM lock.
    private final ArrayList<Pending> queue = new ArrayList<>();
    private long sequence;
    private static final class Pending {
        final PlatformTask task;
        final JSONObject signal;
        final CountDownLatch ready = new CountDownLatch(1);
        long id;
        volatile Exception error;
        Pending(PlatformTask task, JSONObject signal) { this.task=task; this.signal=signal; }
    }
    PermissionPrompts(MainActivity host) { this.host=host; }
    void await(PlatformTask task, JSONObject signal) throws Exception {
        Pending pending=new Pending(task, new JSONObject(signal.toString()));
        host.runOnUiThread(() -> {
            pending.id=++sequence;
            queue.add(pending);
            show();
        });
        try {
            while (!pending.ready.await(200, TimeUnit.MILLISECONDS)) {
                task.check();
                if (!host.ownsPermissionRequest(task.root)) throw new IOException("Access request belongs to a closed conversation.");
            }
            task.check();
            if (pending.error!=null) throw pending.error;
        } finally {
            host.runOnUiThread(() -> { queue.remove(pending); show(); });
        }
    }
    void changed() { show(); }
    private void show() {
        while (!queue.isEmpty()) {
            Pending pending=queue.get(0);
            try {
                pending.task.check();
                if (!host.ownsPermissionRequest(pending.task.root)) throw new IOException("Access request belongs to a closed conversation.");
                if (!host.permissionNeedsPrompt(pending.signal.getString("key"))) {
                    queue.remove(0);pending.ready.countDown();continue;
                }
                JSONObject prompt=new JSONObject(pending.signal.toString())
                    .put("request_id",pending.id).put("agent_id",pending.task.id);
                host.showPermissionRequest(prompt);return;
            } catch (Exception error) {
                pending.error=error;queue.remove(0);pending.ready.countDown();
            }
        }
        host.showPermissionRequest(new JSONObject());
    }
    void resolve(JSONObject command) throws Exception {
        if (queue.isEmpty() || queue.get(0).id!=command.getLong("request_id"))
            throw new IOException("This access request is no longer active.");
        Pending pending=queue.get(0);
        pending.task.check();
        if (!host.ownsPermissionRequest(pending.task.root))
            throw new IOException("Access request belongs to a closed conversation.");
        // Persist before releasing the suspended task. A failed save leaves the
        // prompt active, and MainActivity restores the previous policy.
        if (command.optBoolean("stop")) pending.task.cancel();
        else host.savePermission(pending.signal.getString("key"),command.getBoolean("allowed"));
        queue.remove(0);pending.ready.countDown();show();
    }
}
