package pro.yashchauhan.glob_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Shared helpers for all Glob home-screen widgets. The app writes JSON; these draw it. */
object Kit {
    val rowRoot = intArrayOf(R.id.r1, R.id.r2, R.id.r3, R.id.r4, R.id.r5)
    val rowDot = intArrayOf(R.id.r1_dot, R.id.r2_dot, R.id.r3_dot, R.id.r4_dot, R.id.r5_dot)
    val rowInit = intArrayOf(R.id.r1_init, R.id.r2_init, R.id.r3_init, R.id.r4_init, R.id.r5_init)
    val rowPhoto = intArrayOf(R.id.r1_photo, R.id.r2_photo, R.id.r3_photo, R.id.r4_photo, R.id.r5_photo)
    val rowTitle = intArrayOf(R.id.r1_title, R.id.r2_title, R.id.r3_title, R.id.r4_title, R.id.r5_title)
    val rowSub = intArrayOf(R.id.r1_sub, R.id.r2_sub, R.id.r3_sub, R.id.r4_sub, R.id.r5_sub)
    val rowTrail = intArrayOf(R.id.r1_trail, R.id.r2_trail, R.id.r3_trail, R.id.r4_trail, R.id.r5_trail)
    val rowBtn = intArrayOf(R.id.r1_btn, R.id.r2_btn, R.id.r3_btn, R.id.r4_btn, R.id.r5_btn)

    val slotRoot = intArrayOf(R.id.p1, R.id.p2, R.id.p3, R.id.p4, R.id.p5)
    val slotOpen = intArrayOf(R.id.p1_open, R.id.p2_open, R.id.p3_open, R.id.p4_open, R.id.p5_open)
    val slotDot = intArrayOf(R.id.p1_dot, R.id.p2_dot, R.id.p3_dot, R.id.p4_dot, R.id.p5_dot)
    val slotInit = intArrayOf(R.id.p1_init, R.id.p2_init, R.id.p3_init, R.id.p4_init, R.id.p5_init)
    val slotPhoto = intArrayOf(R.id.p1_photo, R.id.p2_photo, R.id.p3_photo, R.id.p4_photo, R.id.p5_photo)
    val slotName = intArrayOf(R.id.p1_name, R.id.p2_name, R.id.p3_name, R.id.p4_name, R.id.p5_name)
    val slotB1 = intArrayOf(R.id.p1_b1, R.id.p2_b1, R.id.p3_b1, R.id.p4_b1, R.id.p5_b1)
    val slotB2 = intArrayOf(R.id.p1_b2, R.id.p2_b2, R.id.p3_b2, R.id.p4_b2, R.id.p5_b2)

    val actRoot = intArrayOf(R.id.a1, R.id.a2, R.id.a3, R.id.a4)
    val actBg = intArrayOf(R.id.a1_bg, R.id.a2_bg, R.id.a3_bg, R.id.a4_bg)
    val actIcon = intArrayOf(R.id.a1_icon, R.id.a2_icon, R.id.a3_icon, R.id.a4_icon)
    val actLabel = intArrayOf(R.id.a1_label, R.id.a2_label, R.id.a3_label, R.id.a4_label)

    val tileRoot = intArrayOf(R.id.t1, R.id.t2, R.id.t3)
    val tileBg = intArrayOf(R.id.t1_bg, R.id.t2_bg, R.id.t3_bg)
    val tileLabel = intArrayOf(R.id.t1_label, R.id.t2_label, R.id.t3_label)
    val tileValue = intArrayOf(R.id.t1_value, R.id.t2_value, R.id.t3_value)
    val tileBar = intArrayOf(R.id.t1_bar, R.id.t2_bar, R.id.t3_bar)

    fun json(prefs: SharedPreferences, key: String): JSONObject? = try {
        prefs.getString(key, null)?.let { JSONObject(it) }
    } catch (e: Exception) {
        null
    }

    fun color(hex: String?, fallback: Int): Int = try {
        Color.parseColor(hex)
    } catch (e: Exception) {
        fallback
    }

    fun open(ctx: Context, link: String): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(ctx, MainActivity::class.java, Uri.parse(link))

    fun background(ctx: Context, link: String): PendingIntent =
        HomeWidgetBackgroundIntent.getBroadcast(ctx, Uri.parse(link))

    fun dial(ctx: Context, tel: String): PendingIntent = PendingIntent.getActivity(
        ctx, tel.hashCode(), Intent(Intent.ACTION_DIAL, Uri.parse(tel)),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun icon(name: String?): Int = when (name) {
        "tick" -> R.drawable.gw_ic_circle
        "phone" -> R.drawable.gw_ic_phone
        "call" -> R.drawable.gw_ic_phone
        "video" -> R.drawable.gw_ic_video
        "join" -> R.drawable.gw_ic_video
        "add" -> R.drawable.gw_ic_add
        "chat" -> R.drawable.gw_ic_chat
        "bulb" -> R.drawable.gw_ic_bulb
        "calendar" -> R.drawable.gw_ic_calendar
        else -> R.drawable.gw_ic_chat
    }

    /** A picture the app saved, cut into a circle. Null when there is none. */
    fun circle(path: String?): Bitmap? {
        if (path.isNullOrEmpty()) return null
        return try {
            if (!File(path).exists()) return null
            val src = BitmapFactory.decodeFile(path) ?: return null
            val size = 96
            val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(out)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            canvas.drawCircle(size / 2f, size / 2f, size / 2f, paint)
            paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            val scale = maxOf(size.toFloat() / src.width, size.toFloat() / src.height)
            val w = src.width * scale
            val h = src.height * scale
            canvas.drawBitmap(src, null, RectF((size - w) / 2f, (size - h) / 2f, (size + w) / 2f, (size + h) / 2f), paint)
            out
        } catch (e: Exception) {
            null
        }
    }

    /** Their photo, or a coloured circle with their initial. */
    fun avatar(v: RemoteViews, dot: Int, init: Int, photo: Int, o: JSONObject) {
        val bmp = circle(o.optString("photo", ""))
        if (bmp != null) {
            v.setImageViewBitmap(photo, bmp)
            v.setViewVisibility(photo, View.VISIBLE)
            v.setViewVisibility(dot, View.GONE)
            v.setViewVisibility(init, View.GONE)
        } else {
            v.setViewVisibility(photo, View.GONE)
            v.setViewVisibility(dot, View.VISIBLE)
            v.setViewVisibility(init, View.VISIBLE)
            v.setInt(dot, "setColorFilter", color(o.optString("color"), 0xFFBFE4EE.toInt()))
            v.setTextViewText(init, o.optString("initial", "?"))
        }
    }

    fun action(ctx: Context, v: RemoteViews, viewId: Int, a: JSONObject?) {
        if (a == null) {
            v.setViewVisibility(viewId, View.GONE)
            return
        }
        v.setViewVisibility(viewId, View.VISIBLE)
        v.setImageViewResource(viewId, icon(a.optString("icon")))
        val pending = when {
            a.has("dial") -> dial(ctx, a.optString("dial"))
            a.optBoolean("bg", false) -> background(ctx, a.optString("link"))
            else -> open(ctx, a.optString("link", "glob://home"))
        }
        v.setOnClickPendingIntent(viewId, pending)
    }

    fun list(ctx: Context, d: JSONObject?, fallbackTitle: String, fallbackEmpty: String): RemoteViews {
        val v = RemoteViews(ctx.packageName, R.layout.gw_list)
        v.setTextViewText(R.id.gw_title, d?.optString("title", fallbackTitle) ?: fallbackTitle)
        v.setTextViewText(R.id.gw_count, d?.optString("count", "") ?: "")
        val rows = d?.optJSONArray("rows") ?: JSONArray()
        for (i in 0 until 5) {
            val r = if (i < rows.length()) rows.optJSONObject(i) else null
            if (r == null) {
                v.setViewVisibility(rowRoot[i], View.GONE)
                continue
            }
            v.setViewVisibility(rowRoot[i], View.VISIBLE)
            v.setTextViewText(rowTitle[i], r.optString("title"))
            v.setTextViewText(rowSub[i], r.optString("sub"))
            v.setViewVisibility(rowSub[i], if (r.optString("sub").isEmpty()) View.GONE else View.VISIBLE)
            v.setTextViewText(rowTrail[i], r.optString("trail"))
            avatar(v, rowDot[i], rowInit[i], rowPhoto[i], r)
            v.setOnClickPendingIntent(rowRoot[i], open(ctx, r.optString("link", "glob://home")))
            action(ctx, v, rowBtn[i], r.optJSONObject("action"))
        }
        val empty = rows.length() == 0
        v.setViewVisibility(R.id.gw_empty, if (empty) View.VISIBLE else View.GONE)
        v.setTextViewText(R.id.gw_empty, d?.optString("empty", fallbackEmpty) ?: fallbackEmpty)
        v.setOnClickPendingIntent(R.id.gw_title, open(ctx, "glob://home"))
        return v
    }

    fun people(ctx: Context, d: JSONObject?, fallbackTitle: String, fallbackEmpty: String): RemoteViews {
        val v = RemoteViews(ctx.packageName, R.layout.gw_people)
        v.setTextViewText(R.id.gw_title, d?.optString("title", fallbackTitle) ?: fallbackTitle)
        v.setTextViewText(R.id.gw_count, d?.optString("count", "") ?: "")
        val list = d?.optJSONArray("people") ?: JSONArray()
        for (i in 0 until 5) {
            val p = if (i < list.length()) list.optJSONObject(i) else null
            if (p == null) {
                v.setViewVisibility(slotRoot[i], View.GONE)
                continue
            }
            v.setViewVisibility(slotRoot[i], View.VISIBLE)
            v.setTextViewText(slotName[i], p.optString("name"))
            avatar(v, slotDot[i], slotInit[i], slotPhoto[i], p)
            v.setOnClickPendingIntent(slotOpen[i], open(ctx, p.optString("link", "glob://chat")))
            val buttons = p.optJSONArray("buttons") ?: JSONArray()
            action(ctx, v, slotB1[i], buttons.optJSONObject(0))
            action(ctx, v, slotB2[i], buttons.optJSONObject(1))
        }
        v.setViewVisibility(R.id.gw_empty, if (list.length() == 0) View.VISIBLE else View.GONE)
        v.setTextViewText(R.id.gw_empty, d?.optString("empty", fallbackEmpty) ?: fallbackEmpty)
        return v
    }

    fun stats(ctx: Context, d: JSONObject?, fallbackTitle: String): RemoteViews {
        val v = RemoteViews(ctx.packageName, R.layout.gw_stats)
        v.setTextViewText(R.id.gw_title, d?.optString("title", fallbackTitle) ?: fallbackTitle)
        v.setTextViewText(R.id.gw_count, d?.optString("count", "") ?: "")
        val tiles = d?.optJSONArray("tiles") ?: JSONArray()
        for (i in 0 until 3) {
            val t = if (i < tiles.length()) tiles.optJSONObject(i) else null
            if (t == null) {
                v.setViewVisibility(tileRoot[i], View.GONE)
                continue
            }
            v.setViewVisibility(tileRoot[i], View.VISIBLE)
            v.setInt(tileBg[i], "setColorFilter", color(t.optString("color"), 0xFFBFE4EE.toInt()))
            v.setTextViewText(tileLabel[i], t.optString("label"))
            v.setTextViewText(tileValue[i], t.optString("value"))
            if (t.has("progress")) {
                v.setViewVisibility(tileBar[i], View.VISIBLE)
                v.setProgressBar(tileBar[i], 100, t.optInt("progress"), false)
            } else {
                v.setViewVisibility(tileBar[i], View.GONE)
            }
            v.setOnClickPendingIntent(tileRoot[i], open(ctx, t.optString("link", "glob://home")))
        }
        v.setViewVisibility(R.id.gw_empty, if (tiles.length() == 0) View.VISIBLE else View.GONE)
        v.setTextViewText(R.id.gw_empty, d?.optString("empty", "Open Glob to load") ?: "Open Glob to load")
        v.setOnClickPendingIntent(R.id.gw_title, open(ctx, "glob://home"))
        return v
    }
}

abstract class ListWidget(private val key: String, private val title: String, private val empty: String) : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val d = Kit.json(widgetData, key)
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, Kit.list(context, d, title, empty))
    }
}

abstract class PeopleWidget(private val key: String, private val title: String, private val empty: String) : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val d = Kit.json(widgetData, key)
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, Kit.people(context, d, title, empty))
    }
}

abstract class StatsWidget(private val key: String, private val title: String) : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val d = Kit.json(widgetData, key)
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, Kit.stats(context, d, title))
    }
}

/** New task, new idea, chat, call: needs no data, so it works from the first second. */
abstract class ActionsBase : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        val items = listOf(
            Triple("New task", "glob://new/task", "add") to 0xFFBFE4EE.toInt(),
            Triple("New idea", "glob://new/idea", "bulb") to 0xFFF8E58F.toInt(),
            Triple("Messages", "glob://chat", "chat") to 0xFFD0E8B5.toInt(),
            Triple("Call", "glob://call", "phone") to 0xFFF0A48C.toInt(),
        )
        for (id in appWidgetIds) {
            val v = RemoteViews(context.packageName, R.layout.gw_actions)
            for (i in 0 until 4) {
                val (t, color) = items[i]
                val (label, link, icon) = t
                v.setInt(Kit.actBg[i], "setColorFilter", color)
                v.setImageViewResource(Kit.actIcon[i], Kit.icon(icon))
                v.setInt(Kit.actIcon[i], "setColorFilter", 0xFF16161A.toInt())
                v.setTextViewText(Kit.actLabel[i], label)
                v.setOnClickPendingIntent(Kit.actRoot[i], Kit.open(context, link))
            }
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}

// ---- the eleven widgets
class UnreadWidget : ListWidget("w_unread", "Messages", "Open Glob to load")
class TasksWidget : ListWidget("w_tasks", "Today's tasks", "Open Glob to load")
class ActionsWidget : ActionsBase()
class QuickCallWidget : PeopleWidget("w_quickcall", "Quick call", "Open Glob to load")
class NextUpWidget : ListWidget("w_nextup", "Next up", "Open Glob to load")
class CallWidget : ListWidget("w_call", "Call in progress", "Open Glob to load")
class PulseWidget : StatsWidget("w_pulse", "Team pulse")
class IdeasWidget : ListWidget("w_ideas", "Ideas", "Open Glob to load")
class OnlineWidget : PeopleWidget("w_online", "Who's online", "Open Glob to load")
class CrmWidget : ListWidget("w_crm", "CRM follow-ups", "Open Glob to load")
class ProductsWidget : ListWidget("w_products", "Products", "Open Glob to load")
