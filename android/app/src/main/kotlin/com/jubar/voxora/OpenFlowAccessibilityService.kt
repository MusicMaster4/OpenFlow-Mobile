package com.jubar.voxora

import android.accessibilityservice.AccessibilityService
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class OpenFlowAccessibilityService : AccessibilityService() {
    override fun onServiceConnected() {
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        @Volatile
        private var instance: OpenFlowAccessibilityService? = null

        fun pasteText(text: String, keepInClipboard: Boolean): Boolean {
            val service = instance ?: return false
            if (text.isBlank()) return false
            val focused = service.rootInActiveWindow
                ?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
                ?: return false
            if (!focused.isEditable) return false
            val clipboard = service.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val previousClip = if (keepInClipboard) {
                null
            } else {
                runCatching { clipboard.primaryClip }.getOrNull()
            }
            clipboard.setPrimaryClip(ClipData.newPlainText("OpenFlow", text))
            return try {
                focused.performAction(AccessibilityNodeInfo.ACTION_PASTE)
            } finally {
                if (!keepInClipboard) {
                    if (previousClip != null) {
                        clipboard.setPrimaryClip(previousClip)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        clipboard.clearPrimaryClip()
                    } else {
                        clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
                    }
                }
            }
        }
    }
}
