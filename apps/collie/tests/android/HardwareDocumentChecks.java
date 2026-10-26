package org.flexscript.collie;

import android.content.*;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;
import java.io.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;
import org.json.*;

/** Actual provider/grant checks. The picker itself is driven by the host UI test. */
public final class HardwareDocumentChecks {
    final MainActivity host;final File root;final VmHardware.Context context;final JSONArray checks=new JSONArray();int sequence;
    HardwareDocumentChecks(MainActivity host,File root){this.host=host;this.root=root;context=new VmHardware.Context(host,root);}
    public static JSONObject run(MainActivity host,File root)throws Exception{return new HardwareDocumentChecks(host,root).run();}
    public static JSONObject runRevoke(MainActivity host,File root)throws Exception{return new HardwareDocumentChecks(host,root).revoke();}
    public static JSONObject runLive(MainActivity host,File root)throws Exception{return new HardwareDocumentChecks(host,root).live();}
    public static JSONObject runReadGrant(MainActivity host,File root)throws Exception{return new HardwareDocumentChecks(host,root).readGrant();}
    void check(boolean okay,String label)throws Exception{if(!okay)throw new IOException(label);checks.put(label);}
    JSONObject vm(File workspace,String source)throws Exception{source="fn fail(n){let e=db_error();db_io(0,2,e,db_len(e));return n;}"+source.replaceAll("return ([1-9][0-9]*);","return fail($1);");JSONObject o=host.engineAt(workspace,3,new JSONObject().put("config",host.workerConfig(workspace,0)).put("source",source).put("call_id","document-check-"+(++sequence)).put("history",new JSONArray()));if(!o.optString("state").equals("continue")||o.optInt("exit_code")!=0)throw new IOException("Document scenario "+sequence+": "+o);return o;}
    JSONObject vm(String source)throws Exception{return vm(root,source);}
    static String q(String s){return JSONObject.quote(s).replace("\\/","/");}
    JSONObject selection()throws Exception{JSONArray rows=HardwareDocuments.records(host);for(int i=0;i<rows.length();i++){JSONObject r=rows.getJSONObject(i);if(r.getString("scope").equals(HardwareDocuments.scope(root))&&r.getString("ticket").equals("fixture-write")&&r.getString("state").equals("selected"))return r;}throw new IOException("Choose the owned writable test folder first.");}
    JSONObject readGrant()throws Exception{
        JSONObject selected=null;JSONArray rows=HardwareDocuments.records(host);for(int i=0;i<rows.length();i++){JSONObject r=rows.getJSONObject(i);if(r.getString("scope").equals(HardwareDocuments.scope(root))&&r.getString("ticket").equals("fixture-read"))selected=r;}if(selected==null)throw new IOException("Choose the read-only test folder first.");
        Uri uri=Uri.parse(selected.getString("uri"));UriPermission actual=null;for(UriPermission p:host.getContentResolver().getPersistedUriPermissions())if(p.getUri().equals(uri))actual=p;
        check(actual!=null&&actual.isReadPermission()&&!actual.isWritePermission(),"after the last writable selection is forgotten, the independent SDK reports retained read access and released write access for the shared URI");
        return new JSONObject().put("ok",true).put("checks",checks);
    }
    JSONObject run()throws Exception{
        JSONObject r=selection();String grant=r.getString("id");Uri uri=Uri.parse(r.getString("uri"));ContentResolver resolver=host.getContentResolver();boolean persisted=false;for(UriPermission p:resolver.getPersistedUriPermissions())if(p.getUri().equals(uri)&&p.isReadPermission()&&p.isWritePermission())persisted=true;
        check(persisted,"the independent ContentResolver reports a real persisted read/write folder grant returned by Android's picker");
        Uri rootUri=DocumentsContract.buildDocumentUriUsingTree(uri,DocumentsContract.getTreeDocumentId(uri));String expected;try(Cursor c=resolver.query(rootUri,new String[]{DocumentsContract.Document.COLUMN_DISPLAY_NAME},null,null,null)){check(c!=null&&c.moveToFirst(),"the independent provider query resolves the user-selected root");expected=c.getString(0);}
        String tree=vm("fn main(){let h=document_tree_open("+q(grant)+");if !h{return 1;}let d=document_info(db_word(h),\"root\");if !worker_equal(db_word(device_field(d,\"name\")),"+q(expected)+"){return 2;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");
        try{
            check(true,"the actual VM sees the same provider root name through a workspace-owned document tree");
            File other=new File(root,"document-foreign");if(!new File(other,"files").mkdirs())throw new IOException("Cannot create document isolation fixture");
            vm(other,"fn main(){if document_tree_open("+q(grant)+"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_grant\"){return 2;}if device_info("+q(tree)+"){return 3;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_handle\"){return 4;}let p=document_trees(0,16);if db_word(device_field(p,\"total\")){return 5;}return 0;}");
            check(true,"a second actual VM workspace cannot enumerate the grant, open its saved ID or inspect its live handle");
            vm("fn main(){if document_info("+q(tree)+",\"content://com.android.externalstorage.documents/document/primary:outside\"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"stale_document\"){return 2;}if document_children("+q(tree)+",\"root\",-1,1)||document_children("+q(tree)+",\"root\",0,17){return 3;}if document_create("+q(tree)+",\"root\",\"../outside\",\"text/plain\"){return 4;}if document_delete("+q(tree)+",\"root\")||document_rename("+q(tree)+",\"root\",\"renamed\"){return 5;}return 0;}");
            check(true,"raw URI input, invalid page bounds, path-like names and selected-root mutation fail through typed VM errors");
            // Keep each VM batch within its unchanged execution deadline while
            // retaining the same actual SDK stream across the two executions.
            String[] opened=vm("fn main(){let d=document_create("+q(tree)+",\"root\",\"payload.bin\",\"application/octet-stream\");if !d{return 1;}let n=device_field(d,\"id\");let h=document_file_open("+q(tree)+",db_word(n),\"rwt\");if !h{return 2;}let b=alloc(32768);let i=0;while i<32768{store8(b+i,i%256);i=i+1;}if db_word(device_write(db_word(h),db_blob(b,32768)))!=32768{return 3;}db_io(0,1,db_word(n),db_bytes(n));db_io(0,1,\"\\n\",1);db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout").split("\\n",-1);
            if(opened.length!=2)throw new IOException("Missing actual document/stream tokens");String node=opened[0],stream=opened[1];
            vm("fn main(){let h="+q(stream)+";let b=alloc(23);let i=0;while i<23{store8(b+i,i);i=i+1;}if db_word(device_write(h,db_blob(b,23)))!=23{return 4;}if db_word(document_seek(h,32760))!=32760{return 5;}let v=device_read(h,64,1000);if db_bytes(v)!=31{return 6;}i=0;while i<31{if load8(db_word(v)+i)!=(32760+i)%256{return 7;}i=i+1;}if db_kind(device_read(h,1,1000))!=0{return 8;}if !device_close(h){return 9;}return 0;}");
            check(true,"actual provider streams carry all256 byte values across a32768-byte VM frame, a second write, seek, a short final read and EOF");
            HardwareDocuments.Tree owned=VmHardware.handle(context,tree,HardwareDocuments.Tree.class);Uri payload=owned.node(node);
            try(InputStream in=resolver.openInputStream(payload)){check(in!=null,"the independent provider opens the agent-created file");int n=0;byte[] buffer=new byte[4096];for(int count;(count=in.read(buffer))!=-1;){for(int i=0;i<count;i++)if((buffer[i]&255)!=(n+i)%256)throw new IOException("Independent binary mismatch at "+(n+i));n+=count;}check(n==32791,"an independent ContentResolver read verifies every byte and the exact32791-byte file length");}
            vm("fn main(){let h=document_typed_open("+q(tree)+","+q(node)+",\"application/octet-stream\");if !h{return 1;}let i=0;while i<32791{let v=device_read(db_word(h),32768,1000);if db_kind(v)!=3{return 2;}let j=0;while j<db_bytes(v){if load8(db_word(v)+j)!=(i+j)%256{return 3;}j=j+1;}i=i+db_bytes(v);}if db_kind(device_read(db_word(h),1,1000))!=0{return 4;}return device_close(db_word(h))-1;}");
            check(true,"the real provider's typed-asset SDK path returns the same complete binary file through bounded VM reads (ordinary file, not proof of a virtual conversion)");
            android.content.res.AssetFileDescriptor slice=new android.content.res.AssetFileDescriptor(resolver.openFileDescriptor(payload,"r"),17,257);
            String sliced=VmHardware.add(new HardwareDocuments.TypedFile(context,owned,slice,"application/octet-stream"));
            try{vm("fn main(){let v=device_read("+q(sliced)+",512,1000);if db_bytes(v)!=257{return 1;}let i=0;while i<257{if load8(db_word(v)+i)!=(17+i)%256{return 2;}i=i+1;}if db_kind(device_read("+q(sliced)+",512,1000))!=0{return 3;}return 0;}");check(true,"an explicitly SDK-constructed asset slice over the real provider file honors its nonzero17-byte offset,257-byte declared length and EOF without exposing surrounding bytes");}finally{VmHardware.close(context,sliced);}
            vm("fn main(){let h=document_file_open("+q(tree)+","+q(node)+",\"r\");if !h{return 1;}if device_write(db_word(h),db_text(\"no\")){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),\"read_only\"){return 3;}if !device_close(db_word(h)){return 4;}return 0;}");
            check(true,"a read-only actual SDK stream rejects generic device_write even under a writable tree selection");
            String renamed=vm("fn main(){let d=document_rename("+q(tree)+","+q(node)+",\"renamed.bin\");if !d{return 1;}if document_info("+q(tree)+","+q(node)+"){return 2;}let id=device_field(d,\"id\");db_io(0,1,db_word(id),db_bytes(id));return 0;}").getString("stdout");
            try(Cursor c=resolver.query(owned.node(renamed),new String[]{DocumentsContract.Document.COLUMN_DISPLAY_NAME},null,null,null)){check(c!=null&&c.moveToFirst()&&c.getString(0).equals("renamed.bin"),"a VM rename changes actual provider metadata and invalidates the prior document token");}
            vm("fn main(){if db_word(document_delete("+q(tree)+","+q(renamed)+"))!=1{return 1;}if document_info("+q(tree)+","+q(renamed)+"){return 2;}let d=document_create("+q(tree)+",\"root\",\"nested\",\"vnd.android.document/directory\");if !d{return 3;}let id=db_word(device_field(d,\"id\"));let page=document_children("+q(tree)+",id,0,16);if !page||db_word(device_field(page,\"total\")){return 4;}if db_word(document_delete("+q(tree)+",id))!=1{return 5;}return 0;}");
            check(true,"the actual provider creates and removes a nested folder, deletes the renamed file and expires its token");
            vm("fn main(){let all=db_list();let i=0;while i<7{let h=document_tree_open("+q(grant)+");if !h{return 1;}db_add(all,h);i=i+1;}if document_tree_open("+q(grant)+"){return 2;}if !worker_equal(db_word(db_at(device_error(),0)),\"resource_limit\"){return 3;}i=0;while i<7{if !device_close(db_word(db_at(all,i))){return 4;}i=i+1;}return 0;}");
            check(true,"eight live tree resources enforce the app bound, and explicit closes release capacity");
        }finally{VmHardware.close(context,tree);}
        return new JSONObject().put("ok",true).put("checks",checks).put("physical_devices_verified",false);
    }
    JSONObject revoke()throws Exception{
        JSONObject r=selection();String id=r.getString("id"),tree=vm("fn main(){let h=document_tree_open("+q(id)+");if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");Uri uri=Uri.parse(r.getString("uri"));host.getContentResolver().releasePersistableUriPermission(uri,Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
        check(HardwareDocuments.granted(host,uri)==0,"the actual Android persisted URI grant is released independently of the adapter");
        vm("fn main(){if device_info("+q(tree)+"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"permission_revoked\"){return 2;}if document_tree_open("+q(id)+"){return 3;}if !worker_equal(db_word(db_at(device_error(),0)),\"permission_revoked\"){return 4;}return 0;}");
        check(true,"real OS-grant revocation closes the existing tree and prevents reopening its durable ID without silently asking again");
        return new JSONObject().put("ok",true).put("checks",checks).put("physical_devices_verified",false);
    }
    void ui(Runnable action)throws Exception{CountDownLatch done=new CountDownLatch(1);AtomicReference<Throwable> error=new AtomicReference<>();host.runOnUiThread(()->{try{action.run();}catch(Throwable e){error.set(e);}finally{done.countDown();}});if(!done.await(4,TimeUnit.SECONDS))throw new IOException("Document UI fixture timed out");if(error.get()!=null)throw new IOException(error.get());}
    JSONObject live()throws Exception{
        String grant=selection().getString("id"),id=vm("fn main(){let h=document_tree_open("+q(grant)+");if !h{return 1;}db_io(0,1,db_word(h),db_bytes(h));return 0;}").getString("stdout");HardwareDocuments.Tree tree=VmHardware.handle(context,id,HardwareDocuments.Tree.class);
        java.lang.reflect.Method save=MainActivity.class.getDeclaredMethod("savePermission",String.class,Object.class);save.setAccessible(true);ExecutorService executor=Executors.newSingleThreadExecutor();Future<JSONObject> running=null;
        try{
            running=executor.submit(()->host.engineAt(root,3,new JSONObject().put("config",host.workerConfig(root,0)).put("source","fn main(){let i=0;while i<10000{device_wait("+q(id)+",1000);i=i+1;}return 1;}").put("history",new JSONArray())));
            java.lang.reflect.Field active=VmHardware.class.getDeclaredField("active");active.setAccessible(true);boolean waiting=false;long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);
            while(System.nanoTime()<end&&!waiting){Object operation=active.get(null);if(operation!=null){java.lang.reflect.Field io=operation.getClass().getDeclaredField("cancelIO");io.setAccessible(true);waiting=io.get(operation)!=null;}if(!waiting){if(running.isDone())throw new IOException("Document VM exited before revocation: "+running.get());Thread.sleep(10);}}
            check(waiting,"the actual VM is blocked in hardware I/O before its Documents permission changes");
            ui(()->{try{save.invoke(host,"documents",false);}catch(Exception e){throw new RuntimeException(e);}});
            JSONObject stopped=running.get(4,TimeUnit.SECONDS);check(stopped.optString("state").equals("error")&&stopped.optString("stderr").toLowerCase(java.util.Locale.ROOT).contains("cancel"),"changing Documents to Deny on the real UI thread cancels the running VM program");
            check(tree.closed&&!host.workerConfig(root,0).getJSONObject("permissions").optBoolean("documents"),"conversation revocation closes the owned tree and persists the changed policy");
            vm("fn main(){if document_tree_open("+q(grant)+"){return 1;}if !worker_equal(db_word(db_at(device_error(),0)),\"permission_denied\"){return 2;}return 0;}");check(true,"a subsequent actual VM cannot reopen a persisted folder after conversation permission is denied");
        }finally{if(running!=null&&!running.isDone()){VmHardware.cancel();running.cancel(true);}executor.shutdownNow();VmHardware.closeWorkspace(root);ui(()->{try{save.invoke(host,"documents",true);}catch(Exception e){throw new RuntimeException(e);}});}
        return new JSONObject().put("ok",true).put("checks",checks).put("physical_devices_verified",false);
    }
}
