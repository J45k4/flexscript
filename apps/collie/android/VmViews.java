package org.flexscript.collie;

import android.graphics.*;
import android.util.AtomicFile;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.json.*;

/**
 * Immutable, bounded image snapshots outside the guest's filesystem
 * capability.
 */
final class VmViews {
  private static final ThreadLocal<File> SESSION = new ThreadLocal<>();
  private static final int MAX_IMAGE = 524288;
  static void begin(File session) { SESSION.set(session); }
  static void end() { SESSION.remove(); }
  static File image(File session, String id) throws IOException {
    if (session == null || !id.matches("[a-f0-9]{64}"))
      throw new IOException("Invalid preview ID.");
    File dir = new File(session, "previews");
    File file = new File(dir, id + ".jpg");
    if (!file.isFile())
      throw new FileNotFoundException("Image preview is unavailable.");
    if (file.length() > MAX_IMAGE)
      throw new IOException("Image preview exceeds its limit.");
    return file;
  }
  private static byte[] bytes(File file) throws IOException {
    try (InputStream in = new FileInputStream(file);
         ByteArrayOutputStream out = new ByteArrayOutputStream()) {
      byte[] buffer = new byte[8192];
      int n;
      while ((n = in.read(buffer)) != -1) {
        if (out.size() + n > MAX_IMAGE)
          throw new IOException("Image preview exceeds its limit.");
        out.write(buffer, 0, n);
      }
      return out.toByteArray();
    }
  }
  static byte[] capture(byte[] input) {
    return capture(input, null);
  }
  static byte[] capturePhoto(File input) {
    return capture(null, input);
  }
  private static byte[] capture(byte[] input, File photo) {
    Bitmap decoded = null, opaque = null;
    try {
      File session = SESSION.get();
      if (session == null)
        throw new IOException("No image workspace is active.");
      if (photo == null && (input.length < 1 || input.length > 2097152))
        throw new IOException("Images must be at most 2 MiB.");
      if (photo != null && (photo.length() < 1 || photo.length() > 33554432))
        throw new IOException("Photos must be at most 32 MiB.");
      BitmapFactory.Options bounds = new BitmapFactory.Options();
      bounds.inJustDecodeBounds = true;
      if (photo != null) BitmapFactory.decodeFile(photo.getAbsolutePath(), bounds);
      else BitmapFactory.decodeByteArray(input, 0, input.length, bounds);
      if (!(photo != null && bounds.outMimeType != null && bounds.outMimeType.startsWith("image/")) &&
          !("image/png".equals(bounds.outMimeType) ||
            "image/jpeg".equals(bounds.outMimeType) ||
            "image/webp".equals(bounds.outMimeType)))
        throw new IOException("Supported images are PNG, JPEG and WebP.");
      if (bounds.outWidth < 1 || bounds.outHeight < 1 ||
          bounds.outWidth > 16384 || bounds.outHeight > 16384 ||
          (long)bounds.outWidth * bounds.outHeight > (photo == null ? 24000000 : 100000000))
        throw new IOException(
            photo == null ? "Image dimensions exceed the 24 megapixel decode limit." : "Photo dimensions exceed the 100 megapixel decode limit.");
      BitmapFactory.Options options = new BitmapFactory.Options();
      options.inSampleSize = 1;
      while (Math.max(bounds.outWidth, bounds.outHeight) /
                 options.inSampleSize >
             1536)
        options.inSampleSize *= 2;
      decoded = photo != null ? BitmapFactory.decodeFile(photo.getAbsolutePath(), options)
                              : BitmapFactory.decodeByteArray(input, 0, input.length, options);
      if (decoded == null)
        throw new IOException("Cannot decode this image.");
      try {
        android.media.ExifInterface exif =
            photo != null ? new android.media.ExifInterface(photo.getAbsolutePath())
                          : new android.media.ExifInterface(new ByteArrayInputStream(input));
        int orientation = exif.getAttributeInt(
            android.media.ExifInterface.TAG_ORIENTATION, 1);
        Matrix rotate = new Matrix();
        if (orientation == 2)
          rotate.setScale(-1, 1);
        else if (orientation == 3)
          rotate.setRotate(180);
        else if (orientation == 4)
          rotate.setScale(1, -1);
        else if (orientation == 5) {
          rotate.setRotate(90);
          rotate.postScale(-1, 1);
        } else if (orientation == 6)
          rotate.setRotate(90);
        else if (orientation == 7) {
          rotate.setRotate(-90);
          rotate.postScale(-1, 1);
        } else if (orientation == 8)
          rotate.setRotate(-90);
        if (!rotate.isIdentity()) {
          Bitmap oriented =
              Bitmap.createBitmap(decoded, 0, 0, decoded.getWidth(),
                                  decoded.getHeight(), rotate, true);
          if (oriented != decoded) {
            decoded.recycle();
            decoded = oriented;
          }
        }
      } catch (IOException
                   unsupportedMetadata) { /* Pixel decoding still succeeded. */
      }
      opaque = Bitmap.createBitmap(decoded.getWidth(), decoded.getHeight(),
                                   Bitmap.Config.RGB_565);
      Canvas canvas = new Canvas(opaque);
      canvas.drawColor(Color.WHITE);
      canvas.drawBitmap(decoded, 0, 0, null);
      ByteArrayOutputStream encoded = new ByteArrayOutputStream();
      for (int quality : new int[] {90, 75, 55}) {
        encoded.reset();
        if (!opaque.compress(Bitmap.CompressFormat.JPEG, quality, encoded))
          throw new IOException("Cannot encode image preview.");
        if (encoded.size() <= MAX_IMAGE)
          break;
      }
      if (encoded.size() > MAX_IMAGE)
        throw new IOException("Normalized image exceeds 512 KiB.");
      byte[] data = encoded.toByteArray();
      byte[] digest = MessageDigest.getInstance("SHA-256").digest(data);
      StringBuilder key = new StringBuilder();
      for (byte b : digest)
        key.append(String.format(java.util.Locale.ROOT, "%02x", b & 255));
      File dir = new File(session, "previews");
      if (!dir.isDirectory() && !dir.mkdirs())
        throw new IOException("Cannot create image preview directory.");
      File target = new File(dir, key + ".jpg");
      if (!target.isFile()) {
        String[] names = dir.list();
        if (names == null || names.length >= 128)
          throw new IOException(
              "This conversation reached its 128 image snapshot limit.");
        AtomicFile file = new AtomicFile(target);
        FileOutputStream out = null;
        try {
          out = file.startWrite();
          out.write(data);
          file.finishWrite(out);
        } catch (Exception error) {
          if (out != null)
            file.failWrite(out);
          throw error;
        }
      }
      return new JSONObject()
          .put("type", "image")
          .put("image_id", key.toString())
          .put("width", opaque.getWidth())
          .put("height", opaque.getHeight())
          .put("bytes", data.length)
          .put("mime", "image/jpeg")
          .toString()
          .getBytes(StandardCharsets.UTF_8);
    } catch (Exception | OutOfMemoryError error) {
      try {
        return new JSONObject()
            .put("error", error instanceof OutOfMemoryError
                              ? "Image cannot fit in memory."
                              : error.getMessage())
            .toString()
            .getBytes(StandardCharsets.UTF_8);
      } catch (Exception impossible) {
        return "{\"error\":\"Cannot view image.\"}".getBytes(
            StandardCharsets.UTF_8);
      }
    } finally {
      if (decoded != null)
        decoded.recycle();
      if (opaque != null)
        opaque.recycle();
    }
  }
  static byte[] snapshotBytes(byte[] identifier) throws Exception {
    File session = SESSION.get();
    if (session == null) throw new IOException("No image workspace.");
    return bytes(image(session, new String(identifier, StandardCharsets.UTF_8)));
  }
}
