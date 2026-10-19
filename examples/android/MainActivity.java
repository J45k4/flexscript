package org.flexscript.demo;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.io.FileOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.BufferedReader;
import java.io.FileReader;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.charset.StandardCharsets;

public final class MainActivity extends Activity {
    static { System.loadLibrary("flexscript"); }
    private static native long render(ByteBuffer pixels, int width, int height, long touches);
    private static synchronized native long jitProbe(ByteBuffer stats);
    private static synchronized native long runJitCases(ByteBuffer requests, ByteBuffer results);
    private final ByteBuffer jitStats = ByteBuffer.allocateDirect(80).order(ByteOrder.LITTLE_ENDIAN);
    private volatile boolean jitReady;
    private long jitPassed, jitCases, jitHits;
    private long nativeResult, pixelChecksum;
    private final ByteBuffer pixels = ByteBuffer.allocateDirect(128 * 128 * 4);
    private final Bitmap bitmap = Bitmap.createBitmap(128, 128, Bitmap.Config.ARGB_8888);
    private long touches;
    private TextView status;
    private ImageView canvas;

    private TextView text(String value, int size, int color) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setPadding(0, 16, 0, 16);
        return view;
    }

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        if (state != null) touches = state.getLong("touches");
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(48, 96, 48, 48);
        layout.setBackgroundColor(Color.rgb(15, 22, 40));
        layout.addView(text("Flexscript on Android", 28, Color.WHITE));
        layout.addView(text("A canvas drawn by your Flexscript program", 16, Color.rgb(178, 193, 220)));
        canvas = new ImageView(this);
        canvas.setScaleType(ImageView.ScaleType.FIT_CENTER);
        canvas.setContentDescription("Flexscript canvas. Tap to change colors.");
        canvas.setClickable(true);
        canvas.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View view) { touches++; update(); }
        });
        layout.addView(canvas, new LinearLayout.LayoutParams(-1, 0, 1));
        status = text("Loading", 22, Color.WHITE);
        status.setContentDescription("Flexscript result");
        layout.addView(status);
        layout.addView(text("Tap the canvas to run again", 16, Color.rgb(178, 193, 220)));
        setContentView(layout);
        update();
        new Thread(new Runnable() {
            @Override public void run() {
                try (InputStream input = getAssets().open("jit-cases.bin")) {
                    ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                    byte[] chunk = new byte[8192];
                    int size;
                    while ((size = input.read(chunk)) != -1) bytes.write(chunk, 0, size);
                    byte[] payload = bytes.toByteArray();
                    ByteBuffer requests = ByteBuffer.allocateDirect(payload.length).order(ByteOrder.LITTLE_ENDIAN);
                    requests.put(payload);
                    jitCases = requests.getLong(0);
                    ByteBuffer results = ByteBuffer.allocateDirect((int)(40 + jitCases * 80)).order(ByteOrder.LITTLE_ENDIAN);
                    long summary = runJitCases(requests, results);
                    jitPassed = summary < 0 ? summary : summary >>> 32;
                    jitHits = results.getLong(32);
                    byte[] records = new byte[results.capacity()];
                    results.rewind();
                    results.get(records);
                    try (FileOutputStream file = openFileOutput("jit-results.bin", MODE_PRIVATE)) {
                        file.write(records);
                    }
                } catch (Exception error) {
                    jitPassed = -1;
                    Log.e("FlexscriptAndroid", "JIT tests failed", error);
                }
                jitReady = true;
                runOnUiThread(new Runnable() {
                    @Override public void run() { updateStatus(); }
                });
            }
        }, "flexscript-jit-tests").start();
    }

    private String memoryPermissions(long address) {
        try (BufferedReader maps = new BufferedReader(new FileReader("/proc/self/maps"))) {
            String line;
            while ((line = maps.readLine()) != null) {
                String[] fields = line.split(" +");
                String[] range = fields[0].split("-");
                long start = Long.parseLong(range[0], 16), end = Long.parseLong(range[1], 16);
                if (address >= start && address < end) return fields[1];
            }
        } catch (Exception error) { Log.e("FlexscriptAndroid", "JIT mapping check failed", error); }
        return "missing";
    }

    private void update() {
        nativeResult = render(pixels, 128, 128, touches);
        pixels.rewind();
        bitmap.copyPixelsFromBuffer(pixels);
        canvas.setImageBitmap(bitmap);
        long checksum = 0;
        for (int i = 0; i < pixels.capacity(); i++) {
            checksum = (checksum * 31 + (pixels.get(i) & 255)) & 0xffffffffL;
        }
        pixelChecksum = checksum;
        updateStatus();
    }

    private void updateStatus() {
        long result = nativeResult;
        long answer = result >>> 32;
        long frames = (result >>> 16) & 65535;
        long nativeTouches = result & 65535;
        long jit = jitReady ? jitProbe(jitStats) : 0;
        String permissions = jitReady ? memoryPermissions(jitStats.getLong(64)) : "pending";
        status.setText(result < 0 ? "Program error: " + result
            : "Native result: " + answer + "\nJIT result: " + jit + " (" + jitPassed + "/" + jitCases + ")\nTouches: " + nativeTouches + "\nFrames: " + frames);
        String record = "{\"result\":" + answer + ",\"touches\":" + nativeTouches
            + ",\"frames\":" + frames + ",\"raw\":" + result + ",\"pixels\":" + pixelChecksum + ",\"jit\":" + jit
            + ",\"jitPassed\":" + jitPassed + ",\"jitCases\":" + jitCases
            + ",\"jitCacheHits\":" + jitHits + ",\"jitCached\":" + jitStats.getLong(32)
            + ",\"jitPermissions\":\"" + permissions + "\"}";
        Log.i("FlexscriptAndroid", record);
        try (FileOutputStream file = openFileOutput("status.json", MODE_PRIVATE)) {
            file.write(record.getBytes(StandardCharsets.UTF_8));
        } catch (java.io.IOException error) {
            Log.e("FlexscriptAndroid", "Cannot save result", error);
        }
    }

    @Override public void onSaveInstanceState(Bundle state) {
        state.putLong("touches", touches);
        super.onSaveInstanceState(state);
    }
}
