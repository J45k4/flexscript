package org.flexscript.collie.uiprobe;

import android.app.*;
import android.graphics.Rect;
import android.os.Bundle;
import android.util.Xml;
import android.view.accessibility.AccessibilityNodeInfo;
import java.io.*;
import org.xmlpull.v1.XmlSerializer;

/** Separate owned test APK: introspection must not stop the service being tested. */
public final class UiProbe extends Instrumentation {
    int count;
    @Override public void onCreate(Bundle args){super.onCreate(args);start();}
    @Override public void onStart(){Bundle result=new Bundle();AccessibilityNodeInfo root=null;try{
        UiAutomation automation=getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES);
        try{automation.waitForIdle(100,2000);}catch(java.util.concurrent.TimeoutException ignored){}
        long deadline=android.os.SystemClock.elapsedRealtime()+5000;do{root=automation.getRootInActiveWindow();if(root!=null)break;Thread.sleep(50);}while(android.os.SystemClock.elapsedRealtime()<deadline);if(root==null)throw new IOException("No active SDK UI root after transition deadline");
        File file=new File(getTargetContext().getFilesDir(),"hierarchy.xml");try(OutputStream out=new FileOutputStream(file)){XmlSerializer xml=Xml.newSerializer();xml.setOutput(out,"UTF-8");xml.startDocument("UTF-8",true);xml.startTag(null,"hierarchy");node(xml,root,0);xml.endTag(null,"hierarchy");xml.endDocument();}
        result.putString("result","ok");result.putInt("nodes",count);finish(0,result);
    }catch(Exception e){result.putString("error",e.toString());finish(1,result);}finally{if(root!=null)root.recycle();}}
    static String text(CharSequence value){if(value==null)return "";int n=Math.min(value.length(),4096);if(n>0&&n<value.length()&&Character.isHighSurrogate(value.charAt(n-1)))n--;return value.subSequence(0,n).toString();}
    void node(XmlSerializer xml,AccessibilityNodeInfo n,int depth)throws Exception{
        if(++count>2048||depth>64)throw new IOException("Owned UI tree exceeded fixture bounds");Rect b=new Rect();n.getBoundsInScreen(b);
        xml.startTag(null,"node");xml.attribute(null,"text",n.isPassword()?"":text(n.getText()));xml.attribute(null,"content-desc",n.isPassword()?"":text(n.getContentDescription()));xml.attribute(null,"class",text(n.getClassName()));xml.attribute(null,"package",text(n.getPackageName()));xml.attribute(null,"resource-id",text(n.getViewIdResourceName()));xml.attribute(null,"clickable",Boolean.toString(n.isClickable()));xml.attribute(null,"checked",Boolean.toString(n.isChecked()));xml.attribute(null,"password",Boolean.toString(n.isPassword()));xml.attribute(null,"bounds","["+b.left+","+b.top+"]["+b.right+","+b.bottom+"]");
        for(int i=0;i<n.getChildCount();i++){AccessibilityNodeInfo child=n.getChild(i);if(child!=null)try{node(xml,child,depth+1);}finally{child.recycle();}}xml.endTag(null,"node");
    }
}
