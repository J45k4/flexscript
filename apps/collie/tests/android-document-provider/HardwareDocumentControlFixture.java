package org.flexscript.collie.documentfixture;

import android.content.*;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;

/** Test-certificate control plane, separate from normal SAF document permissions. */
public final class HardwareDocumentControlFixture extends ContentProvider {
    @Override public boolean onCreate(){return true;}
    @Override public Bundle call(String method,String arg,Bundle extras){HardwareDocumentProviderFixture provider=HardwareDocumentProviderFixture.instance;if(provider==null)throw new IllegalStateException("The SDK document provider has not initialized");if(!method.startsWith("collie_fixture_"))throw new UnsupportedOperationException();return provider.call(method,arg,extras);}
    @Override public Cursor query(Uri uri,String[] projection,String selection,String[] args,String sort){throw new UnsupportedOperationException();}
    @Override public String getType(Uri uri){return null;}
    @Override public Uri insert(Uri uri,ContentValues values){throw new UnsupportedOperationException();}
    @Override public int delete(Uri uri,String selection,String[] args){throw new UnsupportedOperationException();}
    @Override public int update(Uri uri,ContentValues values,String selection,String[] args){throw new UnsupportedOperationException();}
}
