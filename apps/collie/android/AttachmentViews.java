package org.flexscript.collie;

import android.app.*;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.view.*;
import android.widget.*;
import java.io.File;
import org.json.JSONObject;

/**
 * Local text and image viewers. No HTML, scripts, remote URLs or external
 * intents.
 */
final class AttachmentViews {
  static void attachment(Activity a, LinearLayout parent, JSONObject file,
                         File session, Runnable remove) {
    String path = file.optString("path");
    LinearLayout tile = new LinearLayout(a);
    tile.setGravity(Gravity.CENTER_VERTICAL);
    tile.setPadding(dp(a, 10), dp(a, 8), dp(a, 6), dp(a, 8));
    GradientDrawable background = new GradientDrawable();
    background.setColor(CollieUi.SURFACE_HIGH);
    background.setCornerRadius(dp(a, 12));
    tile.setBackground(background);
    LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(dp(a, 224), dp(a, 72));
    params.setMargins(0, dp(a, 4), dp(a, 8), dp(a, 8));
    parent.addView(tile, params);
    if (file.has("image_id")) {
      try {
        ImageView thumb = new ImageView(a);
        thumb.setImageBitmap(bitmap(session, file, true));
        thumb.setScaleType(ImageView.ScaleType.CENTER_CROP);
        tile.addView(thumb, new LinearLayout.LayoutParams(dp(a, 48), dp(a, 48)));
        tile.setContentDescription("Open attached image: " + path);
        tile.setOnClickListener(v -> show(a, file, session));
      } catch (Exception unavailable) { /* The filename remains usable. */ }
    }
    LinearLayout description = new LinearLayout(a);
    description.setOrientation(LinearLayout.VERTICAL);
    description.setPadding(dp(a, 8), 0, dp(a, 4), 0);
    TextView name = label(a, path.startsWith("/") ? path.substring(1) : path, 13, CollieUi.TEXT);
    name.setMaxLines(1);
    name.setEllipsize(android.text.TextUtils.TruncateAt.MIDDLE);
    description.addView(name);
    long size = file.optLong("file_bytes");
    description.addView(label(a, size < 1024 ? size + " B" : String.format(java.util.Locale.ROOT, "%.1f KB", size / 1024.0), 11, CollieUi.MUTED));
    tile.addView(description, new LinearLayout.LayoutParams(0, -2, 1));
    if (remove != null) {
      TextView close = label(a, "×", 24, CollieUi.MUTED);
      close.setGravity(Gravity.CENTER);
      close.setContentDescription("Remove attachment: " + path);
      close.setOnClickListener(v -> remove.run());
      tile.addView(close, new LinearLayout.LayoutParams(dp(a, 44), dp(a, 48)));
    }
  }
  private static int dp(Activity a, int n) {
    return (int)(n * a.getResources().getDisplayMetrics().density + .5f);
  }
  private static TextView label(Activity a, String text, int size, int color) {
    TextView v = new TextView(a);
    v.setText(text);
    v.setTextColor(color);
    v.setTextSize(size);
    return v;
  }
  private static final java.util
      .Map<String, java.lang.ref.WeakReference<Bitmap>> THUMBS =
      new java.util.HashMap<>();
  private static Bitmap bitmap(File session, JSONObject view, boolean thumb)
      throws Exception {
    String path =
        VmViews.image(session, view.getString("image_id")).getAbsolutePath();
    if (thumb) {
      java.lang.ref.WeakReference<Bitmap> cached = THUMBS.get(path);
      if (cached != null && cached.get() != null)
        return cached.get();
    }
    BitmapFactory.Options options = new BitmapFactory.Options();
    options.inPreferredConfig = Bitmap.Config.RGB_565;
    options.inSampleSize = 1;
    if (thumb)
      while (Math.max(view.optInt("width"), view.optInt("height")) /
                 options.inSampleSize >
             256)
        options.inSampleSize *= 2;
    Bitmap image = BitmapFactory.decodeFile(path, options);
    if (thumb && image != null) {
      if (THUMBS.size() > 512)
        THUMBS.entrySet().removeIf(entry -> entry.getValue().get() == null);
      THUMBS.put(path, new java.lang.ref.WeakReference<>(image));
    }
    return image;
  }
  static void add(Activity a, LinearLayout parent, JSONObject view,
                  File session) {
    String type = view.optString("type"), path = view.optString("path");
    if (!type.equals("file") && !type.equals("image"))
      return;
    LinearLayout card = new LinearLayout(a);
    card.setOrientation(LinearLayout.VERTICAL);
    card.setPadding(dp(a, 12), dp(a, 12), dp(a, 12), dp(a, 12));
    GradientDrawable background = new GradientDrawable();
    background.setColor(CollieUi.SURFACE_HIGH);
    background.setCornerRadius(dp(a, 10));
    card.setBackground(background);
    LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
    params.topMargin = dp(a, 10);
    parent.addView(card, params);
    TextView title =
        label(a, (type.equals("image") ? "Image · " : "File · ") + path, 14,
              CollieUi.ACCENT);
    title.setTypeface(Typeface.create("sans-serif-medium", 0));
    card.addView(title);
    if (type.equals("image")) {
      try {
        Bitmap bitmap = bitmap(session, view, true);
        if (bitmap == null)
          throw new IllegalArgumentException("Cannot decode preview.");
        ImageView image = new ImageView(a);
        image.setImageBitmap(bitmap);
        image.setScaleType(ImageView.ScaleType.FIT_CENTER);
        image.setAdjustViewBounds(true);
        image.setMaxHeight(dp(a, 220));
        image.setContentDescription("Image preview: " + path);
        LinearLayout.LayoutParams imageParams =
            new LinearLayout.LayoutParams(-1, -2);
        imageParams.topMargin = dp(a, 10);
        card.addView(image, imageParams);
      } catch (Exception error) {
        card.addView(label(a, "Image preview unavailable", 12, CollieUi.MUTED));
      }
    } else {
      TextView excerpt = label(a, view.optString("text"), 12, CollieUi.TEXT);
      excerpt.setTypeface(Typeface.MONOSPACE);
      excerpt.setMaxLines(3);
      excerpt.setPadding(0, dp(a, 8), 0, 0);
      card.addView(excerpt);
    }
    TextView action =
        label(a, type.equals("image") ? "Open image" : "Open file", 12,
              CollieUi.ACCENT);
    action.setPadding(0, dp(a, 12), 0, 0);
    card.addView(action);
    card.setContentDescription(
        (type.equals("image") ? "Open image: " : "Open file: ") + path);
    card.setFocusable(true);
    card.setOnClickListener(v -> show(a, view, session));
  }
  private static void show(Activity a, JSONObject view, File session) {
    Dialog dialog = new Dialog(a);
    LinearLayout root = new LinearLayout(a);
    root.setOrientation(LinearLayout.VERTICAL);
    root.setBackgroundColor(CollieUi.BG);
    root.setPadding(dp(a, 18), dp(a, 20), dp(a, 18), dp(a, 20));
    LinearLayout header = new LinearLayout(a);
    header.setGravity(Gravity.CENTER_VERTICAL);
    TextView title = label(a, view.optString("path"), 18, CollieUi.TEXT);
    header.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
    TextView close = label(a, "Close", 14, CollieUi.ACCENT);
    close.setPadding(dp(a, 16), dp(a, 12), dp(a, 4), dp(a, 12));
    close.setContentDescription("Close preview");
    close.setOnClickListener(v -> dialog.dismiss());
    header.addView(close);
    root.addView(header);
    if (view.optString("type").equals("image")) {
      TextView size = label(a,
                            view.optInt("width") + " × " +
                                view.optInt("height") + " · Pinch to zoom",
                            12, CollieUi.MUTED);
      root.addView(size);
      try {
        Bitmap bitmap = bitmap(session, view, false);
        if (bitmap == null)
          throw new IllegalArgumentException("Cannot decode preview.");
        Zoom image = new Zoom(a, bitmap);
        image.setContentDescription("Full image: " + view.optString("path"));
        root.addView(image, new LinearLayout.LayoutParams(-1, 0, 1));
        dialog.setOnDismissListener(ignored -> {
          image.setImageDrawable(null);
          bitmap.recycle();
        });
      } catch (Exception error) {
        root.addView(label(a, "Image preview unavailable", 14, CollieUi.ERROR));
      }
    } else {
      long offset = view.optLong("offset"), count = view.optLong("bytes");
      root.addView(
          label(a,
                "Bytes " + offset + "–" + (offset + count) +
                    (view.optBoolean("truncated") ? " · More available" : ""),
                12, CollieUi.MUTED));
      ScrollView scroll = new ScrollView(a);
      TextView content = label(a, view.optString("text"), 14, CollieUi.TEXT);
      content.setTypeface(Typeface.MONOSPACE);
      content.setTextIsSelectable(true);
      content.setLineSpacing(dp(a, 4), 1);
      content.setPadding(0, dp(a, 16), 0, dp(a, 16));
      scroll.addView(content);
      root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
    }
    dialog.setContentView(root);
    dialog.show();
    dialog.getWindow().setLayout(-1, -1);
  }
  private static final class Zoom extends ImageView {
    private final Matrix transform = new Matrix();
    private final ScaleGestureDetector scale;
    private final Bitmap bitmap;
    private float x, y, factor = 1;
    Zoom(Activity a, Bitmap value) {
      super(a);
      bitmap = value;
      setImageBitmap(value);
      setScaleType(ScaleType.MATRIX);
      scale = new ScaleGestureDetector(
          a, new ScaleGestureDetector.SimpleOnScaleGestureListener() {
            @Override
            public boolean onScale(ScaleGestureDetector detector) {
              float next =
                  Math.max(1, Math.min(8, factor * detector.getScaleFactor()));
              transform.postScale(next / factor, next / factor,
                                  detector.getFocusX(), detector.getFocusY());
              factor = next;
              constrain();
              return true;
            }
          });
    }
    @Override
    protected void onSizeChanged(int w, int h, int oldw, int oldh) {
      super.onSizeChanged(w, h, oldw, oldh);
      transform.setRectToRect(
          new RectF(0, 0, bitmap.getWidth(), bitmap.getHeight()),
          new RectF(0, 0, w, h), Matrix.ScaleToFit.CENTER);
      factor = 1;
      setImageMatrix(transform);
    }
    @Override
    public boolean onTouchEvent(MotionEvent event) {
      scale.onTouchEvent(event);
      if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
        x = event.getX();
        y = event.getY();
      } else if (event.getActionMasked() == MotionEvent.ACTION_MOVE &&
                 !scale.isInProgress() && factor > 1) {
        transform.postTranslate(event.getX() - x, event.getY() - y);
        constrain();
      }
      x = event.getX();
      y = event.getY();
      return true;
    }
    private void constrain() {
      RectF bounds = new RectF(0, 0, bitmap.getWidth(), bitmap.getHeight());
      transform.mapRect(bounds);
      float dx = bounds.width() < getWidth()
                     ? (getWidth() - bounds.width()) / 2 - bounds.left
                 : bounds.left > 0           ? -bounds.left
                 : bounds.right < getWidth() ? getWidth() - bounds.right
                                             : 0;
      float dy = bounds.height() < getHeight()
                     ? (getHeight() - bounds.height()) / 2 - bounds.top
                 : bounds.top > 0              ? -bounds.top
                 : bounds.bottom < getHeight() ? getHeight() - bounds.bottom
                                               : 0;
      transform.postTranslate(dx, dy);
      setImageMatrix(transform);
    }
  }
}
