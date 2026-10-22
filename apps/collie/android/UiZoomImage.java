package org.flexscript.collie;
import android.app.Activity;
import android.graphics.*;
import android.view.*;
import android.widget.ImageView;

/** Android bitmap gesture/matrix adapter. Layout and labels come from Flexscript. */
final class UiZoomImage extends ImageView {
    private final Matrix transform = new Matrix();
    private final ScaleGestureDetector scale;
    private final Bitmap bitmap;
    private float x, y, factor = 1;
    UiZoomImage(Activity a, Bitmap value) {
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
