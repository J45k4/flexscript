package org.flexscript.collie;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.*;
import javax.net.ssl.HttpsURLConnection;
import org.json.JSONObject;

/** A text-only guest capability, separate from the authenticated model transport. */
final class VmInternet {
    private static final int BODY_LIMIT = 32768;
    private static final ExecutorService IO = new ThreadPoolExecutor(0, 1, 30,
        TimeUnit.SECONDS, new SynchronousQueue<Runnable>(), task -> {
            Thread thread = new Thread(task, "collie-vm-internet");
            thread.setDaemon(true);
            return thread;
        });
    private static final class Request {
        volatile boolean cancelled;
        volatile HttpsURLConnection connection;
        void cancel() {
            cancelled = true;
            HttpsURLConnection c = connection;
            if (c != null) c.disconnect();
        }
    }
    private static volatile Request active;
    private static volatile boolean stopped;
    static void begin() { stopped = false; }
    static void cancel() {
        stopped = true;
        Request request = active;
        if (request != null) request.cancel();
    }
    private static void check(Request request) throws IOException {
        if (stopped || request.cancelled || Thread.currentThread().isInterrupted())
            throw new IOException("HTTPS request cancelled.");
    }
    private static URL validate(String value) throws Exception {
        if (value.length() > 4096) throw new IOException("HTTPS URL exceeds 4096 bytes.");
        URI uri = new URI(value);
        if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null ||
            uri.getRawUserInfo() != null || uri.getFragment() != null)
            throw new IOException("Use an absolute HTTPS URL without user information or a fragment.");
        return uri.toURL();
    }
    private static JSONObject fetch(String value, Request request) throws Exception {
        URL url = validate(value);
        for (int redirects = 0; ; redirects++) {
            check(request);
            // Use a fresh transport, independent of the authenticated model connection.
            HttpsURLConnection c = (HttpsURLConnection) url.openConnection(Proxy.NO_PROXY);
            request.connection = c;
            c.setInstanceFollowRedirects(false);
            c.setConnectTimeout(7000);
            c.setReadTimeout(7000);
            c.setUseCaches(false);
            c.setRequestProperty("Cookie", "");
            c.setRequestProperty("Authorization", "");
            c.setRequestProperty("Accept", "text/*, application/json;q=0.9, */*;q=0.1");
            c.setRequestProperty("Accept-Encoding", "identity");
            c.setRequestProperty("User-Agent", "Collie-VM/1");
            try {
                check(request);
                int status = c.getResponseCode();
                check(request);
                if (status == 301 || status == 302 || status == 303 || status == 307 || status == 308) {
                    if (redirects == 3) throw new IOException("HTTPS redirect limit (3) exceeded.");
                    String location = c.getHeaderField("Location");
                    if (location == null) throw new IOException("HTTPS redirect has no Location.");
                    url = validate(new URL(url, location).toString());
                    continue;
                }
                ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                InputStream stream = status >= 400 ? c.getErrorStream() : c.getInputStream();
                if (stream != null) try (InputStream in = stream) {
                    byte[] buffer = new byte[4096];
                    while (bytes.size() <= BODY_LIMIT) {
                        check(request);
                        int n = in.read(buffer, 0, Math.min(buffer.length, BODY_LIMIT + 1 - bytes.size()));
                        if (n < 0) break;
                        bytes.write(buffer, 0, n);
                    }
                }
                check(request);
                byte[] raw = bytes.toByteArray();
                boolean truncated = raw.length > BODY_LIMIT;
                String decoded = new String(raw, 0, Math.min(raw.length, BODY_LIMIT), StandardCharsets.UTF_8);
                // Replacement characters can expand invalid UTF-8. Bound the encoded
                // text too, and never put NUL into the guest's text codec.
                StringBuilder body = new StringBuilder();
                int count = 0;
                for (int at = 0; at < decoded.length();) {
                    int point = decoded.codePointAt(at);
                    at += Character.charCount(point);
                    if (point == 0) point = 0xfffd;
                    int width = point < 128 ? 1 : point < 2048 ? 2 : point < 65536 ? 3 : 4;
                    if (count + width > BODY_LIMIT) { truncated = true; break; }
                    count += width;
                    body.appendCodePoint(point);
                }
                return new JSONObject().put("status", status).put("body", body.toString())
                    .put("url", url.toString()).put("truncated", truncated ? 1 : 0);
            } finally {
                c.disconnect();
                request.connection = null;
            }
        }
    }
    static byte[] get(byte[] input) {
        Request request = new Request();
        active = request;
        Future<JSONObject> future = null;
        try {
            check(request);
            String url = new String(input, StandardCharsets.UTF_8);
            future = IO.submit(() -> fetch(url, request));
            return future.get(8, TimeUnit.SECONDS).toString().getBytes(StandardCharsets.UTF_8);
        } catch (Exception error) {
            String message;
            if (error instanceof TimeoutException) message = "HTTPS request exceeded 8 seconds.";
            else if (error instanceof RejectedExecutionException) message = "Previous HTTPS request is still stopping; retry later.";
            else {
                Throwable cause = error instanceof ExecutionException ? error.getCause() : error;
                message = cause.getMessage();
                if (message == null) message = cause.getClass().getSimpleName();
            }
            try {
                return new JSONObject().put("error", message).toString().getBytes(StandardCharsets.UTF_8);
            } catch (Exception impossible) { return "{\"error\":\"HTTPS request failed.\"}".getBytes(StandardCharsets.UTF_8); }
        } finally {
            request.cancel();
            if (future != null) future.cancel(true);
            active = null;
        }
    }
}
