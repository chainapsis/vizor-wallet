package com.zcash.zcash_wallet

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.example.live_activities.LiveActivityManager

class SyncLiveActivityManager(context: Context) : LiveActivityManager(context) {
    private val context: Context = context.applicationContext
    private val pendingIntent = PendingIntent.getActivity(
        context, 200, Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    override suspend fun buildNotification(
        notification: Notification.Builder,
        event: String,
        data: Map<String, Any>
    ): Notification {
        val remoteView = RemoteViews(context.packageName, R.layout.live_activity)
        val bigRemoteView = RemoteViews(context.packageName, R.layout.live_activity_expanded)

        val status = data["status"] as? String ?: "Syncing..."
        val percentage = data["percentage"] as? Double ?: 0.0
        val scannedHeight = (data["scannedHeight"] as? Number)?.toLong() ?: 0
        val chainTipHeight = (data["chainTipHeight"] as? Number)?.toLong() ?: 0
        val progress = (percentage * 100).toInt()

        // Compact view
        remoteView.setTextViewText(R.id.tv_status, status)
        remoteView.setProgressBar(R.id.pb_sync, 100, progress, false)

        // Expanded view
        bigRemoteView.setTextViewText(R.id.tv_status_expanded, status)
        bigRemoteView.setTextViewText(
            R.id.tv_block_info,
            "Block $scannedHeight / $chainTipHeight"
        )
        bigRemoteView.setProgressBar(R.id.pb_sync_expanded, 100, progress, false)

        return notification
            .setSmallIcon(android.R.drawable.ic_popup_sync)
            .setOngoing(true)
            .setContentTitle("Zcash Wallet")
            .setContentText(status)
            .setContentIntent(pendingIntent)
            .setStyle(Notification.DecoratedCustomViewStyle())
            .setCustomContentView(remoteView)
            .setCustomBigContentView(bigRemoteView)
            .setPriority(Notification.PRIORITY_LOW)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .build()
    }
}
