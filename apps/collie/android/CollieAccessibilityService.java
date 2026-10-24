package org.flexscript.collie;

import android.accessibilityservice.AccessibilityService;
import android.content.Intent;
import android.view.accessibility.AccessibilityEvent;

/** Android alone binds this service after an explicit user change in Settings. */
public final class CollieAccessibilityService extends AccessibilityService {
    @Override protected void onServiceConnected(){super.onServiceConnected();HardwareAccessibility.connected(this);}
    @Override public void onAccessibilityEvent(AccessibilityEvent event){HardwareAccessibility.event(this,event);}
    @Override public void onInterrupt(){HardwareAccessibility.interrupted(this);}
    @Override public boolean onUnbind(Intent intent){HardwareAccessibility.disconnected(this);return super.onUnbind(intent);}
    @Override public void onDestroy(){HardwareAccessibility.disconnected(this);super.onDestroy();}
}
