package org.flexscript.collie;

import android.content.*;
import android.database.Cursor;
import android.net.Uri;
import android.os.*;
import android.provider.DocumentsContract;
import android.system.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import org.json.*;

/** User-selected SAF grants and SDK document resources. No host paths or raw URI input. */
final class HardwareDocuments {
    private static final Object LOCK=new Object();
    private static final Set<Tree> TREES=new HashSet<>();
    private static final int READ=Intent.FLAG_GRANT_READ_URI_PERMISSION, WRITE=Intent.FLAG_GRANT_WRITE_URI_PERMISSION;
    private static final String PREFS="document-trees", RECORDS="records";
    private static final String[] COLUMNS={DocumentsContract.Document.COLUMN_DOCUMENT_ID,DocumentsContract.Document.COLUMN_DISPLAY_NAME,DocumentsContract.Document.COLUMN_MIME_TYPE,DocumentsContract.Document.COLUMN_FLAGS,DocumentsContract.Document.COLUMN_SIZE,DocumentsContract.Document.COLUMN_LAST_MODIFIED};
    static boolean supports(String op){return op.startsWith("document_");}
    static String scope(File root)throws Exception{
        byte[] hash=MessageDigest.getInstance("SHA-256").digest(root.getCanonicalPath().getBytes(StandardCharsets.UTF_8));
        StringBuilder out=new StringBuilder();for(byte b:hash)out.append(String.format(java.util.Locale.ROOT,"%02x",b&255));return out.toString();
    }
    static JSONArray records(android.content.Context host)throws Exception{return new JSONArray(host.getSharedPreferences(PREFS,0).getString(RECORDS,"[]"));}
    static void save(android.content.Context host,JSONArray rows)throws Exception{if(!host.getSharedPreferences(PREFS,0).edit().putString(RECORDS,rows.toString()).commit())throw new IOException("Could not save document-tree ownership.");}
    static JSONObject find(JSONArray rows,String scope,String key,String value)throws Exception{for(int i=0;i<rows.length();i++){JSONObject r=rows.getJSONObject(i);if(scope.equals(r.getString("scope"))&&value.equals(r.optString(key)))return r;}return null;}
    static int granted(android.content.Context host,Uri uri){int flags=0;for(UriPermission p:host.getContentResolver().getPersistedUriPermissions())if(uri.equals(p.getUri()))flags|=(p.isReadPermission()?READ:0)|(p.isWritePermission()?WRITE:0);return flags;}
    static String ticket(JSONArray args)throws Exception{String s=VmHardware.text(args,0,64);if(!s.matches("[A-Za-z0-9_.-]{1,64}"))throw new VmHardware.Failure("invalid_argument","Use a new 1..64 letter/digit/dot/underscore/hyphen picker ticket for each selection.");return s;}
    static JSONObject record(VmHardware.Context c,String id)throws Exception{synchronized(LOCK){JSONObject r=find(records(c.host),scope(c.root),"id",id);if(r==null)throw new VmHardware.Failure("stale_grant","Unknown document-tree grant for this workspace.");return new JSONObject(r.toString());}}
    static Uri selected(JSONObject r)throws Exception{if(!r.getString("state").equals("selected"))throw new VmHardware.Failure("cancelled","The folder picker did not complete. Use a new ticket to ask again.");return Uri.parse(r.getString("uri"));}
    static void allowed(android.content.Context host,JSONObject r)throws Exception{Uri uri=selected(r);int wanted=r.getInt("mode");if((granted(host,uri)&wanted)!=wanted)throw new VmHardware.Failure("permission_revoked","Android's persisted folder grant was revoked. Forget this selection and use a new picker ticket.");}
    static JSONObject describe(android.content.Context host,JSONObject r)throws Exception{int flags=r.has("uri")?granted(host,Uri.parse(r.getString("uri"))):0;return VmHardware.object("id",r.getString("id"),"ticket",r.getString("ticket"),"state",r.getString("state"),"writable",(r.getInt("mode")&WRITE)!=0,"read_granted",(flags&READ)!=0,"write_granted",(flags&WRITE)!=0,"authority",r.has("uri")?Uri.parse(r.getString("uri")).getAuthority():JSONObject.NULL);}
    static void capabilities(VmHardware.Context c,JSONArray out)throws Exception{out.put(VmHardware.object("id","document_trees","implemented",true,"supported",true,"available",JSONObject.NULL,"permission","documents","picker_foreground_required",true,"picker_required_for_new_grants",true,"persisted_grants",true,"max_open_trees",8));}

    // Consent is performed only after the VM has checkpointed and released its lock.
    static Intent picker(VmHardware.Context c,JSONObject request)throws Exception{
        String ticket=request.getString("ticket");int mode=request.getInt("mode");
        synchronized(LOCK){JSONArray rows=records(c.host);String scope=scope(c.root);JSONObject r=find(rows,scope,"ticket",ticket);
            if(r!=null&&!r.getString("state").equals("pending"))return null;
            if(r==null){int owned=0;for(int i=0;i<rows.length();i++)if(scope.equals(rows.getJSONObject(i).getString("scope")))owned++;if(owned>=16||rows.length()>=128)throw new VmHardware.Failure("resource_limit","At most16 saved picker tickets per conversation and128 per app; forget unused selections.");r=VmHardware.object("scope",scope,"id","tree-"+UUID.randomUUID(),"ticket",ticket,"mode",mode,"state","pending");rows.put(r);save(c.host,rows);}
            if(r.getInt("mode")!=mode)throw new VmHardware.Failure("invalid_argument","A picker ticket cannot change its access mode.");
        }
        return new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(mode|Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION|Intent.FLAG_GRANT_PREFIX_URI_PERMISSION);
    }
    static void pickerResult(VmHardware.Context c,JSONObject request,int result,Intent data,boolean abandoned)throws Exception{
        synchronized(LOCK){JSONArray rows=records(c.host);JSONObject r=find(rows,scope(c.root),"ticket",request.getString("ticket"));if(r==null||!r.getString("state").equals("pending"))return;
            Uri uri=data==null?null:data.getData();int wanted=r.getInt("mode");
            if(abandoned||result!=android.app.Activity.RESULT_OK||uri==null){r.put("state","cancelled");save(c.host,rows);return;}
            if(!"content".equals(uri.getScheme())||!DocumentsContract.isTreeUri(uri)||(data.getFlags()&wanted)!=wanted||(data.getFlags()&Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)==0){r.put("state","cancelled");save(c.host,rows);throw new VmHardware.Failure("invalid_response","The picker did not return a persistable document tree with the requested access.");}
            // Record the user's selection before taking its grant, allowing an
            // interrupted callback to recover the selected URI without inventing consent.
            r.put("uri",uri.toString());save(c.host,rows);
            try{c.host.getContentResolver().takePersistableUriPermission(uri,wanted);r.put("state","selected");save(c.host,rows);}
            catch(Exception error){r.put("state","cancelled");save(c.host,rows);releaseUnused(c.host,rows,uri);throw error;}
        }
    }
    static void releaseUnused(android.content.Context host,JSONArray rows,Uri uri)throws Exception{int used=0;for(int i=0;i<rows.length();i++){JSONObject r=rows.getJSONObject(i);if(uri.toString().equals(r.optString("uri"))&&r.getString("state").equals("selected"))used|=r.getInt("mode");}int release=granted(host,uri)&~used;if(release!=0)host.getContentResolver().releasePersistableUriPermission(uri,release);}
    static void abandonPick(VmHardware.Context c,JSONObject request)throws Exception{synchronized(LOCK){JSONArray rows=records(c.host);JSONObject r=find(rows,scope(c.root),"ticket",request.getString("ticket"));if(r==null)return;r.put("state","cancelled");save(c.host,rows);if(r.has("uri"))releaseUnused(c.host,rows,Uri.parse(r.getString("uri")));}}
    static Object pick(VmHardware.Context c,JSONArray args)throws Exception{
        String ticket=ticket(args);int mode=READ|(VmHardware.integer(args,1,0,1)==1?WRITE:0);
        synchronized(LOCK){JSONArray rows=records(c.host);JSONObject r=find(rows,scope(c.root),"ticket",ticket);
            if(r!=null){if(r.getInt("mode")!=mode)throw new VmHardware.Failure("invalid_argument","A picker ticket cannot change its access mode.");
                if(r.getString("state").equals("pending")&&r.has("uri")&&(granted(c.host,Uri.parse(r.getString("uri")))&mode)==mode){r.put("state","selected");save(c.host,rows);}
                if(!r.getString("state").equals("pending")){allowed(c.host,r);return r.getString("id");}
            }
        }
        if(!c.host.hardwareVisible)throw new VmHardware.Failure("foreground_required","Keep Collie visible to choose a folder.");
        throw new VmHardware.Consent(VmHardware.object("type","document_tree","ticket",ticket,"mode",mode));
    }
    static int forget(VmHardware.Context c,String id)throws Exception{
        JSONObject removed;JSONArray remaining=new JSONArray();List<Tree> closing=new ArrayList<>();
        synchronized(LOCK){JSONArray rows=records(c.host);removed=find(rows,scope(c.root),"id",id);if(removed==null)throw new VmHardware.Failure("stale_grant","Unknown document-tree grant for this workspace.");for(int i=0;i<rows.length();i++)if(rows.getJSONObject(i)!=removed)remaining.put(rows.getJSONObject(i));save(c.host,remaining);for(Tree t:TREES)if(t.root.equals(c.root)&&t.grantId.equals(id))closing.add(t);}
        for(Tree t:closing)t.close();
        synchronized(LOCK){if(removed.has("uri"))releaseUnused(c.host,records(c.host),Uri.parse(removed.getString("uri")));}return 1;
    }
    static final class Tree extends VmHardware.Handle {
        final VmHardware.Context context;final String grantId;final Uri uri;final int mode;
        final LinkedHashMap<String,String> nodes=new LinkedHashMap<>();final Set<VmHardware.Handle> streams=new HashSet<>();CancellationSignal active;
        Tree(VmHardware.Context c,JSONObject r)throws Exception{super(c,"documents","document_tree");context=c;grantId=r.getString("id");uri=selected(r);mode=r.getInt("mode");nodes.put("root",DocumentsContract.getTreeDocumentId(uri));}
        void access(VmHardware.Context c)throws Exception{super.access(c);try{JSONObject r=record(c,grantId);allowed(c.host,r);}catch(Exception e){close();throw e;}}
        synchronized CancellationSignal begin()throws Exception{check();if(active!=null)throw new VmHardware.Failure("busy","A document-provider operation is already active for this tree.");active=new CancellationSignal();return active;}
        synchronized void end(CancellationSignal signal){if(active==signal)active=null;}
        synchronized Uri node(String token)throws Exception{check();String id=nodes.get(token);if(id==null)throw new VmHardware.Failure("stale_document","Document tokens belong to one open tree and expire on close or mutation. List it again.");return DocumentsContract.buildDocumentUriUsingTree(uri,id);}
        synchronized String issue(String id)throws Exception{check();if(id==null||id.length()>4096)throw new VmHardware.Failure("invalid_response","The provider returned an invalid document ID.");for(Map.Entry<String,String> n:nodes.entrySet())if(n.getValue().equals(id))return n.getKey();if(nodes.size()>=1024)throw new VmHardware.Failure("resource_limit","At most1024 known document tokens per open tree. Close and reopen to start a fresh traversal.");String token="document-"+UUID.randomUUID();nodes.put(token,id);return token;}
        void writable()throws Exception{if((mode&WRITE)==0)throw new VmHardware.Failure("read_only","This folder selection is read-only; use a new writable picker ticket.");}
        synchronized Object info()throws Exception{check();return VmHardware.object("kind",kind,"grant",grantId,"root","root","writable",(mode&WRITE)!=0,"known_documents",nodes.size());}
        void invalidate()throws Exception{List<VmHardware.Handle> closing;synchronized(this){closing=new ArrayList<>(streams);nodes.clear();nodes.put("root",DocumentsContract.getTreeDocumentId(uri));}for(VmHardware.Handle f:closing)f.close();}
        public void close()throws IOException{CancellationSignal cancelling;List<VmHardware.Handle> closing;synchronized(this){if(closed)return;super.close();cancelling=active;nodes.clear();closing=new ArrayList<>(streams);}if(cancelling!=null)cancelling.cancel();for(VmHardware.Handle f:closing)try{f.close();}catch(IOException ignored){}synchronized(LOCK){TREES.remove(this);}}
    }
    static Object nullable(Cursor cursor,int column)throws Exception{return cursor.isNull(column)?JSONObject.NULL:column==3||column==4||column==5?cursor.getLong(column):bounded(cursor.getString(column),column==2?256:1024);}
    static String bounded(String value,int max)throws Exception{if(value==null||value.length()>max)throw new VmHardware.Failure("size_limit","Document metadata exceeds its bounded SDK field size.");return value;}
    static JSONObject row(Tree tree,Cursor cursor)throws Exception{return VmHardware.object("id",tree.issue(cursor.getString(0)),"name",nullable(cursor,1),"mime_type",nullable(cursor,2),"flags",nullable(cursor,3),"size",nullable(cursor,4),"last_modified_ms",nullable(cursor,5));}
    static JSONObject metadata(Tree tree,Uri uri,CancellationSignal signal)throws Exception{try(Cursor cursor=tree.context.host.getContentResolver().query(uri,COLUMNS,null,null,null,signal)){if(cursor==null||!cursor.moveToFirst())throw new VmHardware.Failure("not_found","The provider no longer contains this document.");return row(tree,cursor);}}
    static String name(JSONArray args,int at)throws Exception{String name=VmHardware.text(args,at,255);if(name.isEmpty()||name.equals(".")||name.equals("..")||name.indexOf('/')>=0||name.indexOf('\\')>=0)throw new VmHardware.Failure("invalid_argument","Use one nonempty document display name without path separators.");return name;}
    static final class DocumentFile extends VmHardware.Handle {
        final Tree tree;final ParcelFileDescriptor descriptor;final String mode;volatile long position;
        DocumentFile(VmHardware.Context c,Tree tree,ParcelFileDescriptor fd,String mode)throws Exception{super(c,"documents","document_file");this.tree=tree;descriptor=fd;this.mode=mode;try{Os.fcntlInt(fd.getFileDescriptor(),OsConstants.F_SETFL,Os.fcntlInt(fd.getFileDescriptor(),OsConstants.F_GETFL,0)|OsConstants.O_NONBLOCK);synchronized(tree){tree.check();tree.streams.add(this);}}catch(Exception error){fd.close();throw error;}}
        void access(VmHardware.Context c)throws Exception{super.access(c);tree.access(c);}
        void ready(int events,int timeout)throws Exception{check();StructPollfd p=new StructPollfd();p.fd=descriptor.getFileDescriptor();p.events=(short)events;if(Os.poll(new StructPollfd[]{p},timeout)==0)throw new VmHardware.Failure("timeout","Document stream I/O timed out.");check();if((p.revents&(OsConstants.POLLERR|OsConstants.POLLNVAL))!=0)throw new VmHardware.Failure("disconnected","Document stream disconnected.");}
        Object read(int limit,int timeout)throws Exception{if(!mode.contains("r"))throw new VmHardware.Failure("write_only","This stream is not readable.");ready(OsConstants.POLLIN,timeout);byte[] bytes=new byte[limit];int n=Os.read(descriptor.getFileDescriptor(),bytes,0,limit);if(n==0)return JSONObject.NULL;position+=n;return VmHardware.bytes(Arrays.copyOf(bytes,n));}
        Object write(byte[] bytes)throws Exception{if(mode.equals("r"))throw new VmHardware.Failure("read_only","This stream is not writable.");ready(OsConstants.POLLOUT,8000);int n=Os.write(descriptor.getFileDescriptor(),bytes,0,bytes.length);position+=n;return n;}
        Object info()throws Exception{check();return VmHardware.object("kind",kind,"grant",tree.grantId,"mode",mode,"bytes_transferred",position,"stat_size",descriptor.getStatSize());}
        public void close()throws IOException{synchronized(this){if(closed)return;super.close();}synchronized(tree){tree.streams.remove(this);}descriptor.close();}
    }
    static final class TypedFile extends VmHardware.Handle {
        final Tree tree;final android.content.res.AssetFileDescriptor asset;final InputStream input;final String mime;long position;
        TypedFile(VmHardware.Context c,Tree tree,android.content.res.AssetFileDescriptor asset,String mime)throws Exception{super(c,"documents","document_typed_file");this.tree=tree;this.asset=asset;this.mime=mime;try{ParcelFileDescriptor fd=asset.getParcelFileDescriptor();Os.fcntlInt(fd.getFileDescriptor(),OsConstants.F_SETFL,Os.fcntlInt(fd.getFileDescriptor(),OsConstants.F_GETFL,0)|OsConstants.O_NONBLOCK);input=asset.createInputStream();synchronized(tree){tree.check();tree.streams.add(this);}}catch(Exception error){asset.close();throw error;}}
        void access(VmHardware.Context c)throws Exception{super.access(c);tree.access(c);}
        Object read(int limit,int timeout)throws Exception{check();StructPollfd p=new StructPollfd();p.fd=asset.getFileDescriptor();p.events=(short)OsConstants.POLLIN;if(Os.poll(new StructPollfd[]{p},timeout)==0)throw new VmHardware.Failure("timeout","Converted document stream timed out.");check();if((p.revents&(OsConstants.POLLERR|OsConstants.POLLNVAL))!=0)throw new VmHardware.Failure("disconnected","Converted document stream disconnected.");byte[] bytes=new byte[limit];int n=input.read(bytes);if(n<0)return JSONObject.NULL;position+=n;return VmHardware.bytes(Arrays.copyOf(bytes,n));}
        Object info()throws Exception{check();return VmHardware.object("kind",kind,"grant",tree.grantId,"mime_type",mime,"bytes_transferred",position,"declared_length",asset.getDeclaredLength());}
        public void close()throws IOException{synchronized(this){if(closed)return;super.close();}synchronized(tree){tree.streams.remove(this);}input.close();}
    }
    static Object call(VmHardware.Context c,String op,JSONArray args)throws Exception{
        if(op.equals("document_pick"))return pick(c,args);
        if(op.equals("document_trees")){int offset=VmHardware.integer(args,0,0,128),limit=VmHardware.integer(args,1,1,16);JSONArray own=new JSONArray();synchronized(LOCK){JSONArray rows=records(c.host);String scope=scope(c.root);for(int i=0;i<rows.length();i++){JSONObject r=rows.getJSONObject(i);if(scope.equals(r.getString("scope")))own.put(describe(c.host,r));}}JSONArray page=new JSONArray();int end=Math.min(own.length(),offset+limit);for(int i=offset;i<end;i++)page.put(own.get(i));return VmHardware.object("trees",page,"next",end<own.length()?end:-1,"total",own.length());}
        if(op.equals("document_forget"))return forget(c,VmHardware.text(args,0,128));
        if(op.equals("document_tree_open")){JSONObject r=record(c,VmHardware.text(args,0,128));allowed(c.host,r);Tree tree;synchronized(LOCK){if(TREES.size()>=8)throw new VmHardware.Failure("resource_limit","At most8 document trees may be open in the app.");tree=new Tree(c,r);TREES.add(tree);}return VmHardware.add(tree);}
        if(op.equals("document_seek")){DocumentFile f=VmHardware.handle(c,VmHardware.text(args,0,128),DocumentFile.class);f.access(c);long offset=VmHardware.longInteger(args,1,0,Long.MAX_VALUE);try{return Os.lseek(f.descriptor.getFileDescriptor(),offset,OsConstants.SEEK_SET);}catch(ErrnoException error){if(error.errno==OsConstants.ESPIPE)throw new VmHardware.Failure("unsupported_operation","This provider supplied a non-seekable stream.");throw error;}}
        Tree tree=VmHardware.handle(c,VmHardware.text(args,0,128),Tree.class);tree.access(c);CancellationSignal signal=tree.begin();VmHardware.blocking(tree);
        try{
            String token=VmHardware.text(args,1,128);Uri node=tree.node(token);ContentResolver resolver=c.host.getContentResolver();
            if(op.equals("document_info"))return metadata(tree,node,signal);
            if(op.equals("document_children")){int offset=VmHardware.integer(args,2,0,1000000),limit=VmHardware.integer(args,3,1,16);Uri children=DocumentsContract.buildChildDocumentsUriUsingTree(tree.uri,DocumentsContract.getDocumentId(node));try(Cursor cursor=resolver.query(children,COLUMNS,null,null,null,signal)){if(cursor==null)throw new VmHardware.Failure("unavailable","The provider returned no directory cursor.");int total=cursor.getCount(),end=Math.min(total,offset+limit);JSONArray page=new JSONArray();for(int i=offset;i<end;i++){VmHardware.check();if(!cursor.moveToPosition(i))throw new VmHardware.Failure("invalid_response","The directory cursor changed during enumeration.");page.put(row(tree,cursor));}return VmHardware.object("documents",page,"next",end<total?end:-1,"total",total,"loading",cursor.getExtras().getBoolean(DocumentsContract.EXTRA_LOADING,false));}}
            if(op.equals("document_file_open")){String mode=VmHardware.text(args,2,3);if(!Arrays.asList("r","w","wt","wa","rw","rwt").contains(mode))throw new VmHardware.Failure("invalid_argument","Use SDK stream mode r/w/wt/wa/rw/rwt; w truncation is provider-dependent.");if(!mode.equals("r"))tree.writable();ParcelFileDescriptor fd=resolver.openFileDescriptor(node,mode,signal);if(fd==null)throw new VmHardware.Failure("unavailable","The provider did not open a stream.");return VmHardware.add(new DocumentFile(c,tree,fd,mode));}
            if(op.equals("document_types")){String filter=VmHardware.text(args,2,256);String[] types=resolver.getStreamTypes(node,filter);JSONArray out=new JSONArray();if(types!=null){if(types.length>64)throw new VmHardware.Failure("size_limit","The provider returned more than64 stream types.");for(String type:types)out.put(bounded(type,256));}return out;}
            if(op.equals("document_typed_open")){String mime=VmHardware.text(args,2,256);if(mime.indexOf('/')<=0||mime.indexOf('*')>=0)throw new VmHardware.Failure("invalid_argument","Choose a concrete stream MIME type from document_types.");android.content.res.AssetFileDescriptor asset=resolver.openTypedAssetFileDescriptor(node,mime,null,signal);if(asset==null)throw new VmHardware.Failure("unavailable","The provider did not open a converted stream.");return VmHardware.add(new TypedFile(c,tree,asset,mime));}
            tree.writable();Uri result;
            if(op.equals("document_create")){String name=name(args,2),mime=VmHardware.text(args,3,256);if(!mime.matches("[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+"))throw new VmHardware.Failure("invalid_argument","Use a concrete MIME type, or vnd.android.document/directory for a folder.");result=DocumentsContract.createDocument(resolver,node,mime,name);}
            else{if(token.equals("root"))throw new VmHardware.Failure("invalid_argument","The selected root cannot be renamed or deleted through this adapter.");
                if(op.equals("document_rename"))result=DocumentsContract.renameDocument(resolver,node,name(args,2));
                else if(op.equals("document_copy"))result=DocumentsContract.copyDocument(resolver,node,tree.node(VmHardware.text(args,2,128)));
                else if(op.equals("document_move"))result=DocumentsContract.moveDocument(resolver,node,tree.node(VmHardware.text(args,2,128)),tree.node(VmHardware.text(args,3,128)));
                else if(op.equals("document_remove")){if(!DocumentsContract.removeDocument(resolver,node,tree.node(VmHardware.text(args,2,128))))throw new VmHardware.Failure("io_error","The provider did not remove this document from its parent.");tree.invalidate();return 1;}
                else if(op.equals("document_delete")){if(!DocumentsContract.deleteDocument(resolver,node))throw new VmHardware.Failure("io_error","The provider did not delete the document.");tree.invalidate();return 1;}
                else throw new VmHardware.Failure("unsupported_operation","Unknown document operation.");}
            if(result==null)throw new VmHardware.Failure("io_error","The document provider did not complete the mutation.");
            if(!tree.uri.getAuthority().equals(result.getAuthority())||!DocumentsContract.isTreeUri(result)||!DocumentsContract.getTreeDocumentId(tree.uri).equals(DocumentsContract.getTreeDocumentId(result)))throw new VmHardware.Failure("invalid_response","The provider returned a document outside the selected tree.");
            tree.invalidate();return metadata(tree,result,signal);
        }catch(FileNotFoundException error){throw new VmHardware.Failure("not_found",MainActivity.safe(error));}
        catch(UnsupportedOperationException error){throw new VmHardware.Failure("unsupported_operation",MainActivity.safe(error));}
        catch(OperationCanceledException error){throw new VmHardware.Failure("cancelled","The document-provider operation was cancelled.");}
        finally{VmHardware.unblocking();tree.end(signal);}
    }
}
