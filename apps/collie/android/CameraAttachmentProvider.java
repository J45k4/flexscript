package org.flexscript.collie;

import android.content.*;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import java.io.*;

/** Grants the camera one temporary output file, outside the VM workspace. */
public final class CameraAttachmentProvider extends ContentProvider {
    static final String AUTHORITY = "org.flexscript.collie.camera";
    static File file(Context context, String name) throws IOException {
        if (name == null || !name.matches("[a-f0-9-]{36}\\.jpg"))
            throw new IOException("Invalid camera attachment.");
        File dir = new File(context.getCacheDir(), "camera");
        if (!dir.isDirectory() && !dir.mkdirs()) throw new IOException("Cannot create camera directory.");
        return new File(dir, name);
    }
    static Uri uri(String name) { return new Uri.Builder().scheme("content").authority(AUTHORITY).appendPath(name).build(); }
    private File target(Uri uri) throws FileNotFoundException {
        try {
            if (!"content".equals(uri.getScheme()) || !AUTHORITY.equals(uri.getAuthority())
                || uri.getPathSegments().size() != 1 || uri.getQuery() != null || uri.getFragment() != null)
                throw new IOException("Invalid camera URI.");
            File target = file(getContext(), uri.getLastPathSegment());
            if (!target.isFile()) throw new IOException("Camera attachment is unavailable.");
            return target;
        } catch (IOException error) { throw new FileNotFoundException(error.getMessage()); }
    }
    @Override public boolean onCreate() { return true; }
    @Override public String getType(Uri uri) { return "image/jpeg"; }
    @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        return ParcelFileDescriptor.open(target(uri), ParcelFileDescriptor.parseMode(mode));
    }
    @Override public Cursor query(Uri uri, String[] projection, String selection, String[] args, String sort) {
        try {
            File file = target(uri);
            String[] columns = projection == null ? new String[] {OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE} : projection;
            MatrixCursor cursor = new MatrixCursor(columns);
            Object[] row = new Object[columns.length];
            for (int i = 0; i < columns.length; i++) {
                if (OpenableColumns.DISPLAY_NAME.equals(columns[i])) row[i] = file.getName();
                if (OpenableColumns.SIZE.equals(columns[i])) row[i] = file.length();
            }
            cursor.addRow(row); return cursor;
        } catch (FileNotFoundException error) { throw new IllegalArgumentException(error.getMessage()); }
    }
    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] args) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri, String selection, String[] args) { throw new UnsupportedOperationException(); }
}
