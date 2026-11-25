#!/usr/bin/env python3
"""Generates the native Android home-screen widget files into android_overlay/.
The CI build copies them into the android/ project that `flutter create` makes."""
import os, textwrap
ROOT = os.path.join(os.path.dirname(__file__), '..', 'android_overlay')
def w(path, text):
    p = os.path.join(ROOT, path); os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'w').write(text)

NS = 'xmlns:android="http://schemas.android.com/apk/res/android"'
ROWS = 5; SLOTS = 5; ACTS = 4; TILES = 3

# ------------------------------------------------------------------ colours
w('res/values/gw_colors.xml', '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="gw_card">#FFF7F7FA</color>
    <color name="gw_text">#FF16161A</color>
    <color name="gw_muted">#FF7C7C86</color>
    <color name="gw_btn">#FFE6E6EE</color>
    <color name="gw_dark">#FF16161A</color>
</resources>
''')
w('res/values-night/gw_colors.xml', '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="gw_card">#FF1F1F24</color>
    <color name="gw_text">#FFF2F2F5</color>
    <color name="gw_muted">#FF9A9AA3</color>
    <color name="gw_btn">#FF34343A</color>
    <color name="gw_dark">#FF16161A</color>
</resources>
''')

# ------------------------------------------------------------------ drawables
w('res/drawable/gw_bg.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<shape {NS} android:shape="rectangle">
    <solid android:color="@color/gw_card" />
    <corners android:radius="24dp" />
</shape>
''')
w('res/drawable/gw_circle.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<shape {NS} android:shape="oval">
    <solid android:color="#FFFFFFFF" />
</shape>
''')
w('res/drawable/gw_btn_bg.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<shape {NS} android:shape="oval">
    <solid android:color="@color/gw_btn" />
</shape>
''')
w('res/drawable/gw_tile.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<shape {NS} android:shape="rectangle">
    <solid android:color="#FFFFFFFF" />
    <corners android:radius="18dp" />
</shape>
''')
ICONS = {
 'circle': 'M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM12,20c-4.42,0 -8,-3.58 -8,-8s3.58,-8 8,-8 8,3.58 8,8 -3.58,8 -8,8z',
 'phone': 'M6.62,10.79c1.44,2.83 3.76,5.14 6.59,6.59l2.2,-2.2c0.27,-0.27 0.67,-0.36 1.02,-0.24 1.12,0.37 2.33,0.57 3.57,0.57 0.55,0 1,0.45 1,1V20c0,0.55 -0.45,1 -1,1 -9.39,0 -17,-7.61 -17,-17 0,-0.55 0.45,-1 1,-1h3.5c0.55,0 1,0.45 1,1 0,1.25 0.2,2.45 0.57,3.57 0.11,0.35 0.03,0.74 -0.25,1.02l-2.2,2.2z',
 'video': 'M17,10.5V7c0,-0.55 -0.45,-1 -1,-1H4c-0.55,0 -1,0.45 -1,1v10c0,0.55 0.45,1 1,1h12c0.55,0 1,-0.45 1,-1v-3.5l4,4v-11l-4,4z',
 'add': 'M19,13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z',
 'chat': 'M20,2H4c-1.1,0 -2,0.9 -2,2v18l4,-4h14c1.1,0 2,-0.9 2,-2V4c0,-1.1 -0.9,-2 -2,-2z',
 'bulb': 'M9,21c0,0.55 0.45,1 1,1h4c0.55,0 1,-0.45 1,-1v-1H9v1zM12,2C8.14,2 5,5.14 5,9c0,2.38 1.19,4.47 3,5.74V17c0,0.55 0.45,1 1,1h6c0.55,0 1,-0.45 1,-1v-2.26c1.81,-1.27 3,-3.36 3,-5.74 0,-3.86 -3.14,-7 -7,-7z',
 'calendar': 'M19,3h-1V1h-2v2H8V1H6v2H5c-1.11,0 -1.99,0.9 -1.99,2L3,19c0,1.1 0.89,2 2,2h14c1.1,0 2,-0.9 2,-2V5c0,-1.1 -0.9,-2 -2,-2zM19,19H5V8h14v11z',
}
for name, path in ICONS.items():
    w(f'res/drawable/gw_ic_{name}.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<vector {NS}
    android:width="24dp" android:height="24dp"
    android:viewportWidth="24" android:viewportHeight="24"
    android:tint="@color/gw_text">
    <path android:fillColor="#FFFFFFFF" android:pathData="{path}" />
</vector>
''')

# ------------------------------------------------------------------ layouts
def header():
    return '''    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:gravity="center_vertical" android:paddingBottom="4dp">
        <TextView android:id="@+id/gw_title" android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1" android:maxLines="1" android:ellipsize="end" android:textColor="@color/gw_text" android:textSize="15sp" android:textStyle="bold" />
        <TextView android:id="@+id/gw_count" android:layout_width="wrap_content" android:layout_height="wrap_content" android:maxLines="1" android:textColor="@color/gw_muted" android:textSize="12sp" />
    </LinearLayout>
'''
def avatar(prefix, size):
    return f'''<FrameLayout android:layout_width="{size}dp" android:layout_height="{size}dp">
                <ImageView android:id="@+id/{prefix}_dot" android:layout_width="match_parent" android:layout_height="match_parent" android:src="@drawable/gw_circle" />
                <TextView android:id="@+id/{prefix}_init" android:layout_width="match_parent" android:layout_height="match_parent" android:gravity="center" android:textColor="@color/gw_dark" android:textSize="{max(12, size // 3)}sp" android:textStyle="bold" />
                <ImageView android:id="@+id/{prefix}_photo" android:layout_width="match_parent" android:layout_height="match_parent" android:scaleType="centerCrop" android:visibility="gone" />
            </FrameLayout>'''

rows = ''
for i in range(1, ROWS + 1):
    rows += f'''        <LinearLayout android:id="@+id/r{i}" android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:gravity="center_vertical" android:paddingTop="4dp" android:paddingBottom="4dp" android:visibility="gone">
            {avatar(f"r{i}", 34)}
            <LinearLayout android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1" android:orientation="vertical" android:layout_marginStart="10dp" android:layout_marginEnd="6dp">
                <TextView android:id="@+id/r{i}_title" android:layout_width="match_parent" android:layout_height="wrap_content" android:maxLines="1" android:ellipsize="end" android:textColor="@color/gw_text" android:textSize="14sp" android:textStyle="bold" />
                <TextView android:id="@+id/r{i}_sub" android:layout_width="match_parent" android:layout_height="wrap_content" android:maxLines="1" android:ellipsize="end" android:textColor="@color/gw_muted" android:textSize="12sp" />
            </LinearLayout>
            <TextView android:id="@+id/r{i}_trail" android:layout_width="wrap_content" android:layout_height="wrap_content" android:maxLines="1" android:textColor="@color/gw_text" android:textSize="12sp" android:textStyle="bold" />
            <ImageView android:id="@+id/r{i}_btn" android:layout_width="34dp" android:layout_height="34dp" android:layout_marginStart="6dp" android:padding="7dp" android:background="@drawable/gw_btn_bg" android:visibility="gone" />
        </LinearLayout>
'''
w('res/layout/gw_list.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout {NS} android:id="@+id/gw_root" android:layout_width="match_parent" android:layout_height="match_parent" android:orientation="vertical" android:background="@drawable/gw_bg" android:padding="14dp">
{header()}{rows}        <TextView android:id="@+id/gw_empty" android:layout_width="match_parent" android:layout_height="wrap_content" android:paddingTop="10dp" android:textColor="@color/gw_muted" android:textSize="13sp" android:visibility="gone" />
</LinearLayout>
''')

slots = ''
for i in range(1, SLOTS + 1):
    slots += f'''        <LinearLayout android:id="@+id/p{i}" android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1" android:orientation="vertical" android:gravity="center_horizontal" android:visibility="gone">
            <LinearLayout android:id="@+id/p{i}_open" android:layout_width="wrap_content" android:layout_height="wrap_content" android:orientation="vertical" android:gravity="center_horizontal">
                {avatar(f"p{i}", 46)}
                <TextView android:id="@+id/p{i}_name" android:layout_width="56dp" android:layout_height="wrap_content" android:gravity="center" android:maxLines="1" android:ellipsize="end" android:paddingTop="3dp" android:textColor="@color/gw_text" android:textSize="11sp" />
            </LinearLayout>
            <LinearLayout android:layout_width="wrap_content" android:layout_height="wrap_content" android:orientation="horizontal" android:paddingTop="3dp">
                <ImageView android:id="@+id/p{i}_b1" android:layout_width="28dp" android:layout_height="28dp" android:padding="6dp" android:background="@drawable/gw_btn_bg" android:visibility="gone" />
                <ImageView android:id="@+id/p{i}_b2" android:layout_width="28dp" android:layout_height="28dp" android:layout_marginStart="4dp" android:padding="6dp" android:background="@drawable/gw_btn_bg" android:visibility="gone" />
            </LinearLayout>
        </LinearLayout>
'''
w('res/layout/gw_people.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout {NS} android:id="@+id/gw_root" android:layout_width="match_parent" android:layout_height="match_parent" android:orientation="vertical" android:background="@drawable/gw_bg" android:padding="14dp">
{header()}    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:paddingTop="6dp">
{slots}    </LinearLayout>
    <TextView android:id="@+id/gw_empty" android:layout_width="match_parent" android:layout_height="wrap_content" android:paddingTop="10dp" android:textColor="@color/gw_muted" android:textSize="13sp" android:visibility="gone" />
</LinearLayout>
''')

acts = ''
for i in range(1, ACTS + 1):
    acts += f'''        <LinearLayout android:id="@+id/a{i}" android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1" android:orientation="vertical" android:gravity="center_horizontal">
            <FrameLayout android:layout_width="46dp" android:layout_height="46dp">
                <ImageView android:id="@+id/a{i}_bg" android:layout_width="match_parent" android:layout_height="match_parent" android:src="@drawable/gw_circle" />
                <ImageView android:id="@+id/a{i}_icon" android:layout_width="match_parent" android:layout_height="match_parent" android:padding="12dp" />
            </FrameLayout>
            <TextView android:id="@+id/a{i}_label" android:layout_width="wrap_content" android:layout_height="wrap_content" android:paddingTop="4dp" android:maxLines="1" android:textColor="@color/gw_text" android:textSize="11sp" />
        </LinearLayout>
'''
w('res/layout/gw_actions.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout {NS} android:id="@+id/gw_root" android:layout_width="match_parent" android:layout_height="match_parent" android:orientation="horizontal" android:gravity="center_vertical" android:background="@drawable/gw_bg" android:paddingLeft="10dp" android:paddingRight="10dp" android:paddingTop="8dp" android:paddingBottom="8dp">
{acts}</LinearLayout>
''')

tiles = ''
for i in range(1, TILES + 1):
    tiles += f'''        <FrameLayout android:id="@+id/t{i}" android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1" android:layout_marginEnd="6dp" android:visibility="gone">
            <ImageView android:id="@+id/t{i}_bg" android:layout_width="match_parent" android:layout_height="match_parent" android:scaleType="fitXY" android:src="@drawable/gw_tile" />
            <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="vertical" android:padding="10dp">
                <TextView android:id="@+id/t{i}_label" android:layout_width="match_parent" android:layout_height="wrap_content" android:maxLines="1" android:textColor="@color/gw_dark" android:textSize="11sp" />
                <TextView android:id="@+id/t{i}_value" android:layout_width="match_parent" android:layout_height="wrap_content" android:maxLines="1" android:textColor="@color/gw_dark" android:textSize="22sp" android:textStyle="bold" />
                <ProgressBar android:id="@+id/t{i}_bar" style="?android:attr/progressBarStyleHorizontal" android:layout_width="match_parent" android:layout_height="6dp" android:max="100" android:progress="0" android:visibility="gone" />
            </LinearLayout>
        </FrameLayout>
'''
w('res/layout/gw_stats.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout {NS} android:id="@+id/gw_root" android:layout_width="match_parent" android:layout_height="match_parent" android:orientation="vertical" android:background="@drawable/gw_bg" android:padding="14dp">
{header()}    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content" android:orientation="horizontal" android:paddingTop="6dp">
{tiles}    </LinearLayout>
    <TextView android:id="@+id/gw_empty" android:layout_width="match_parent" android:layout_height="wrap_content" android:paddingTop="10dp" android:textColor="@color/gw_muted" android:textSize="13sp" android:visibility="gone" />
</LinearLayout>
''')

# ------------------------------------------------------------------ the eleven widgets
WIDGETS = [
 # class,        base,     layout,       label,                  description,                              height, cells
 ('UnreadWidget',    'List',   'gw_list',    'Glob · Messages',        'Who messaged you, with unread counts',   180, 3),
 ('TasksWidget',     'List',   'gw_list',    "Glob · Today's tasks",   'Open tasks you can tick off',            180, 3),
 ('ActionsWidget',   'Actions','gw_actions', 'Glob · Quick actions',   'New task, new idea, chat and call',       70, 1),
 ('QuickCallWidget', 'People', 'gw_people',  'Glob · Quick call',      'One tap to call the people you talk to', 120, 2),
 ('NextUpWidget',    'List',   'gw_list',    'Glob · Next up',         'Your next events and follow-ups',        180, 3),
 ('CallWidget',      'List',   'gw_list',    'Glob · Call in progress','Join a group call that is happening',     90, 2),
 ('PulseWidget',     'Stats',  'gw_stats',   'Glob · Team pulse',      'Tasks done, open questions, feasibility',110, 2),
 ('IdeasWidget',     'List',   'gw_list',    'Glob · Ideas',           'Latest ideas coloured by status',        180, 3),
 ('OnlineWidget',    'People', 'gw_people',  "Glob · Who's online",    'Teammates who are active right now',     120, 2),
 ('CrmWidget',       'List',   'gw_list',    'Glob · CRM follow-ups',  'Leads to follow up today',               180, 3),
 ('ProductsWidget',  'List',   'gw_list',    'Glob · Products',        'Which products are up or down',          140, 2),
]
strings = ['<?xml version="1.0" encoding="utf-8"?>', '<resources>']
manifest = ''
for cls, base, layout, label, desc, h, cells in WIDGETS:
    key = cls[:-6].lower()
    strings.append(f'    <string name="gw_label_{key}">{label.replace(chr(39), chr(92)+chr(39))}</string>')
    strings.append(f'    <string name="gw_desc_{key}">{desc}</string>')
    w(f'res/xml/gw_info_{key}.xml', f'''<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider {NS}
    android:minWidth="250dp"
    android:minHeight="{h}dp"
    android:targetCellWidth="4"
    android:targetCellHeight="{cells}"
    android:minResizeWidth="180dp"
    android:minResizeHeight="{min(h, 70)}dp"
    android:resizeMode="horizontal|vertical"
    android:updatePeriodMillis="1800000"
    android:initialLayout="@layout/{layout}"
    android:description="@string/gw_desc_{key}"
    android:widgetCategory="home_screen" />
''')
    manifest += f'''        <receiver android:name=".{cls}" android:label="@string/gw_label_{key}" android:exported="true">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/gw_info_{key}" />
        </receiver>
'''
strings.append('</resources>')
w('res/values/gw_strings.xml', '\n'.join(strings) + '\n')
manifest += '        <receiver android:name="es.antonborri.home_widget.HomeWidgetBackgroundReceiver" android:exported="false" />\n'
w('manifest_receivers.xml', manifest)

# ------------------------------------------------------------------ Kotlin
def ids(prefix, n, suffix=''):
    return ', '.join(f'R.id.{prefix}{i}{suffix}' for i in range(1, n + 1))

provs = ''
for cls, base, layout, label, desc, h, cells in WIDGETS:
    key = cls[:-6].lower()
    if base == 'List':   provs += f'class {cls} : ListWidget("w_{key}", "{label.split(" · ")[1]}", "Open Glob to load")\n'
    elif base == 'People': provs += f'class {cls} : PeopleWidget("w_{key}", "{label.split(" · ")[1]}", "Open Glob to load")\n'
    elif base == 'Stats':  provs += f'class {cls} : StatsWidget("w_{key}", "{label.split(" · ")[1]}")\n'
    else:                  provs += f'class {cls} : ActionsWidget()\n'
provs = provs.replace('class ActionsWidget : ActionsWidget()', 'class ActionsWidget : ActionsBase()')

kotlin = f'''package pro.yashchauhan.glob_app

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
object Kit {{
    val rowRoot = intArrayOf({ids("r", ROWS)})
    val rowDot = intArrayOf({ids("r", ROWS, "_dot")})
    val rowInit = intArrayOf({ids("r", ROWS, "_init")})
    val rowPhoto = intArrayOf({ids("r", ROWS, "_photo")})
    val rowTitle = intArrayOf({ids("r", ROWS, "_title")})
    val rowSub = intArrayOf({ids("r", ROWS, "_sub")})
    val rowTrail = intArrayOf({ids("r", ROWS, "_trail")})
    val rowBtn = intArrayOf({ids("r", ROWS, "_btn")})

    val slotRoot = intArrayOf({ids("p", SLOTS)})
    val slotOpen = intArrayOf({ids("p", SLOTS, "_open")})
    val slotDot = intArrayOf({ids("p", SLOTS, "_dot")})
    val slotInit = intArrayOf({ids("p", SLOTS, "_init")})
    val slotPhoto = intArrayOf({ids("p", SLOTS, "_photo")})
    val slotName = intArrayOf({ids("p", SLOTS, "_name")})
    val slotB1 = intArrayOf({ids("p", SLOTS, "_b1")})
    val slotB2 = intArrayOf({ids("p", SLOTS, "_b2")})

    val actRoot = intArrayOf({ids("a", ACTS)})
    val actBg = intArrayOf({ids("a", ACTS, "_bg")})
    val actIcon = intArrayOf({ids("a", ACTS, "_icon")})
    val actLabel = intArrayOf({ids("a", ACTS, "_label")})

    val tileRoot = intArrayOf({ids("t", TILES)})
    val tileBg = intArrayOf({ids("t", TILES, "_bg")})
    val tileLabel = intArrayOf({ids("t", TILES, "_label")})
    val tileValue = intArrayOf({ids("t", TILES, "_value")})
    val tileBar = intArrayOf({ids("t", TILES, "_bar")})

    fun json(prefs: SharedPreferences, key: String): JSONObject? = try {{
        prefs.getString(key, null)?.let {{ JSONObject(it) }}
    }} catch (e: Exception) {{
        null
    }}

    fun color(hex: String?, fallback: Int): Int = try {{
        Color.parseColor(hex)
    }} catch (e: Exception) {{
        fallback
    }}

    fun open(ctx: Context, link: String): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(ctx, MainActivity::class.java, Uri.parse(link))

    fun background(ctx: Context, link: String): PendingIntent =
        HomeWidgetBackgroundIntent.getBroadcast(ctx, Uri.parse(link))

    fun dial(ctx: Context, tel: String): PendingIntent = PendingIntent.getActivity(
        ctx, tel.hashCode(), Intent(Intent.ACTION_DIAL, Uri.parse(tel)),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun icon(name: String?): Int = when (name) {{
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
    }}

    /** A picture the app saved, cut into a circle. Null when there is none. */
    fun circle(path: String?): Bitmap? {{
        if (path.isNullOrEmpty()) return null
        return try {{
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
        }} catch (e: Exception) {{
            null
        }}
    }}

    /** Their photo, or a coloured circle with their initial. */
    fun avatar(v: RemoteViews, dot: Int, init: Int, photo: Int, o: JSONObject) {{
        val bmp = circle(o.optString("photo", ""))
        if (bmp != null) {{
            v.setImageViewBitmap(photo, bmp)
            v.setViewVisibility(photo, View.VISIBLE)
            v.setViewVisibility(dot, View.GONE)
            v.setViewVisibility(init, View.GONE)
        }} else {{
            v.setViewVisibility(photo, View.GONE)
            v.setViewVisibility(dot, View.VISIBLE)
            v.setViewVisibility(init, View.VISIBLE)
            v.setInt(dot, "setColorFilter", color(o.optString("color"), 0xFFBFE4EE.toInt()))
            v.setTextViewText(init, o.optString("initial", "?"))
        }}
    }}

    fun action(ctx: Context, v: RemoteViews, viewId: Int, a: JSONObject?) {{
        if (a == null) {{
            v.setViewVisibility(viewId, View.GONE)
            return
        }}
        v.setViewVisibility(viewId, View.VISIBLE)
        v.setImageViewResource(viewId, icon(a.optString("icon")))
        val pending = when {{
            a.has("dial") -> dial(ctx, a.optString("dial"))
            a.optBoolean("bg", false) -> background(ctx, a.optString("link"))
            else -> open(ctx, a.optString("link", "glob://home"))
        }}
        v.setOnClickPendingIntent(viewId, pending)
    }}

    fun list(ctx: Context, d: JSONObject?, fallbackTitle: String, fallbackEmpty: String): RemoteViews {{
        val v = RemoteViews(ctx.packageName, R.layout.gw_list)
        v.setTextViewText(R.id.gw_title, d?.optString("title", fallbackTitle) ?: fallbackTitle)
        v.setTextViewText(R.id.gw_count, d?.optString("count", "") ?: "")
        val rows = d?.optJSONArray("rows") ?: JSONArray()
        for (i in 0 until {ROWS}) {{
            val r = if (i < rows.length()) rows.optJSONObject(i) else null
            if (r == null) {{
                v.setViewVisibility(rowRoot[i], View.GONE)
                continue
            }}
            v.setViewVisibility(rowRoot[i], View.VISIBLE)
            v.setTextViewText(rowTitle[i], r.optString("title"))
            v.setTextViewText(rowSub[i], r.optString("sub"))
            v.setViewVisibility(rowSub[i], if (r.optString("sub").isEmpty()) View.GONE else View.VISIBLE)
            v.setTextViewText(rowTrail[i], r.optString("trail"))
            avatar(v, rowDot[i], rowInit[i], rowPhoto[i], r)
            v.setOnClickPendingIntent(rowRoot[i], open(ctx, r.optString("link", "glob://home")))
            action(ctx, v, rowBtn[i], r.optJSONObject("action"))
        }}
        val empty = rows.length() == 0
        v.setViewVisibility(R.id.gw_empty, if (empty) View.VISIBLE else View.GONE)
        v.setTextViewText(R.id.gw_empty, d?.optString("empty", fallbackEmpty) ?: fallbackEmpty)
        v.setOnClickPendingIntent(R.id.gw_title, open(ctx, "glob://home"))
        return v
    }}

    fun people(ctx: Context, d: JSONObject?, fallbackTitle: String, fallbackEmpty: String): RemoteViews {{
        val v = RemoteViews(ctx.packageName, R.layout.gw_people)
        v.setTextViewText(R.id.gw_title, d?.optString("title", fallbackTitle) ?: fallbackTitle)
        v.setTextViewText(R.id.gw_count, d?.optString("count", "") ?: "")
        val list = d?.optJSONArray("people") ?: JSONArray()
        for (i in 0 until {SLOTS}) {{
            val p = if (i < list.length()) list.optJSONObject(i) else null
            if (p == null) {{
                v.setViewVisibility(slotRoot[i], View.GONE)
                continue
            }}
            v.setViewVisibility(slotRoot[i], View.VISIBLE)
            v.setTextViewText(slotName[i], p.optString("name"))
            avatar(v, slotDot[i], slotInit[i], slotPhoto[i], p)
            v.setOnClickPendingIntent(slotOpen[i], open(ctx, p.optString("link", "glob://chat")))
            val buttons = p.optJSONArray("buttons") ?: JSONArray()
            action(ctx, v, slotB1[i], buttons.optJSONObject(0))
            action(ctx, v, slotB2[i], buttons.optJSONObject(1))
        }}
        v.setViewVisibility(R.id.gw_empty, if (list.length() == 0) View.VISIBLE else View.GONE)
        v.setTextViewText(R.id.gw_empty, d?.optString("empty", fallbackEmpty) ?: fallbackEmpty)
        return v
    }}

    fun stats(ctx: Context, d: JSONObject?, fallbackTitle: String): RemoteViews {{
        val v = RemoteViews(ctx.packageName, R.layout.gw_stats)
        v.setTextViewText(R.id.gw_title, d?.optString("title", fallbackTitle) ?: fallbackTitle)
        v.setTextViewText(R.id.gw_count, d?.optString("count", "") ?: "")
        val tiles = d?.optJSONArray("tiles") ?: JSONArray()
        for (i in 0 until {TILES}) {{
            val t = if (i < tiles.length()) tiles.optJSONObject(i) else null
            if (t == null) {{
                v.setViewVisibility(tileRoot[i], View.GONE)
                continue
            }}
            v.setViewVisibility(tileRoot[i], View.VISIBLE)
            v.setInt(tileBg[i], "setColorFilter", color(t.optString("color"), 0xFFBFE4EE.toInt()))
            v.setTextViewText(tileLabel[i], t.optString("label"))
            v.setTextViewText(tileValue[i], t.optString("value"))
            if (t.has("progress")) {{
                v.setViewVisibility(tileBar[i], View.VISIBLE)
                v.setProgressBar(tileBar[i], 100, t.optInt("progress"), false)
            }} else {{
                v.setViewVisibility(tileBar[i], View.GONE)
            }}
            v.setOnClickPendingIntent(tileRoot[i], open(ctx, t.optString("link", "glob://home")))
        }}
        v.setViewVisibility(R.id.gw_empty, if (tiles.length() == 0) View.VISIBLE else View.GONE)
        v.setTextViewText(R.id.gw_empty, d?.optString("empty", "Open Glob to load") ?: "Open Glob to load")
        v.setOnClickPendingIntent(R.id.gw_title, open(ctx, "glob://home"))
        return v
    }}
}}

abstract class ListWidget(private val key: String, private val title: String, private val empty: String) : HomeWidgetProvider() {{
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {{
        val d = Kit.json(widgetData, key)
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, Kit.list(context, d, title, empty))
    }}
}}

abstract class PeopleWidget(private val key: String, private val title: String, private val empty: String) : HomeWidgetProvider() {{
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {{
        val d = Kit.json(widgetData, key)
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, Kit.people(context, d, title, empty))
    }}
}}

abstract class StatsWidget(private val key: String, private val title: String) : HomeWidgetProvider() {{
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {{
        val d = Kit.json(widgetData, key)
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, Kit.stats(context, d, title))
    }}
}}

/** New task, new idea, chat, call: needs no data, so it works from the first second. */
abstract class ActionsBase : HomeWidgetProvider() {{
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {{
        val items = listOf(
            Triple("New task", "glob://new/task", "add") to 0xFFBFE4EE.toInt(),
            Triple("New idea", "glob://new/idea", "bulb") to 0xFFF8E58F.toInt(),
            Triple("Messages", "glob://chat", "chat") to 0xFFD0E8B5.toInt(),
            Triple("Call", "glob://call", "phone") to 0xFFF0A48C.toInt(),
        )
        for (id in appWidgetIds) {{
            val v = RemoteViews(context.packageName, R.layout.gw_actions)
            for (i in 0 until {ACTS}) {{
                val (t, color) = items[i]
                val (label, link, icon) = t
                v.setInt(Kit.actBg[i], "setColorFilter", color)
                v.setImageViewResource(Kit.actIcon[i], Kit.icon(icon))
                v.setInt(Kit.actIcon[i], "setColorFilter", 0xFF16161A.toInt())
                v.setTextViewText(Kit.actLabel[i], label)
                v.setOnClickPendingIntent(Kit.actRoot[i], Kit.open(context, link))
            }}
            appWidgetManager.updateAppWidget(id, v)
        }}
    }}
}}

// ---- the eleven widgets
{provs}'''
w('kotlin/GlobWidgets.kt', kotlin)
print('generated')
