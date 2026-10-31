package com.mathlessons.app.ui

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.view.WindowManager
import android.webkit.WebView
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.URL

/**
 * يحدد نوع الرابط: يوتيوب/فيميو (يحتاج تضمين WebView) أو ملف فيديو مباشر
 * (رابط موقّت من Supabase Storage يشغَّل مباشرة بمشغّل ExoPlayer).
 */
sealed class VideoSource {
    data class DirectFile(val url: String) : VideoSource()
    data class YouTube(val embedUrl: String) : VideoSource()
    data class Vimeo(val embedUrl: String) : VideoSource()
}

fun resolveVideoSource(url: String): VideoSource {
    val youtubeRegex = Regex("(?:youtube\\.com/watch\\?v=|youtu\\.be/|youtube\\.com/embed/)([a-zA-Z0-9_-]+)")
    val vimeoRegex = Regex("vimeo\\.com/(\\d+)")

    youtubeRegex.find(url)?.let {
        return VideoSource.YouTube("https://www.youtube.com/embed/${it.groupValues[1]}")
    }
    vimeoRegex.find(url)?.let {
        return VideoSource.Vimeo("https://player.vimeo.com/video/${it.groupValues[1]}")
    }
    return VideoSource.DirectFile(url)
}

/**
 * يمنع لقطات الشاشة وتسجيل الشاشة على مستوى النظام أثناء عرض الفيديو
 * (FLAG_SECURE) - نفس الأسلوب المستخدم بتطبيقات مثل Netflix. بصراحة: لا توجد
 * حماية برمجية 100% ضد التصوير بكاميرا خارجية للشاشة - هذا حد معروف لأي
 * حل بدون DRM حقيقي (Widevine).
 */
@Composable
fun SecureScreenWhileVisible() {
    val activity = LocalContext.current as? Activity
    DisposableEffect(Unit) {
        activity?.window?.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        onDispose {
            activity?.window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}

/** مجلد التنزيلات خاص بالتطبيق نفسه (داخلي، غير مرئي لتطبيقات أخرى أو مدير الملفات) */
fun localVideoFile(context: Context, contentId: String): File {
    val dir = File(context.filesDir, "downloads")
    if (!dir.exists()) dir.mkdirs()
    return File(dir, "$contentId.mp4")
}

/** حفظ/استرجاع آخر موضع مشاهدة لكل فيديو - يخزَّن محلياً بجهاز الطالب فقط */
private const val PREFS_NAME = "video_progress"

private fun getSavedPosition(context: Context, contentId: String): Long {
    return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .getLong(contentId, 0L)
}

private fun savePosition(context: Context, contentId: String, positionMs: Long) {
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .edit()
        .putLong(contentId, positionMs)
        .apply()
}

private fun clearSavedPosition(context: Context, contentId: String) {
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        .edit()
        .remove(contentId)
        .apply()
}

/**
 * "متابعة المشاهدة": نحفظ آخر درس توقف فيه الطالب بمنتصف فيديو (عنوان + معرّف)
 * عشان تعرضه شاشة "دروسي" بالأعلى مباشرة بدل ما يدور عليه. تبسيط مقصود: نتتبع
 * آخر درس واحد بس (مو قائمة كاملة لكل الفيديوهات غير المكتملة) - كافي لتجربة
 * مفيدة بدون تعقيد إضافي.
 */
private const val CONTINUE_WATCHING_PREFS = "continue_watching"

fun saveContinueWatching(context: Context, lessonId: String, lessonTitle: String) {
    context.getSharedPreferences(CONTINUE_WATCHING_PREFS, Context.MODE_PRIVATE)
        .edit()
        .putString("lesson_id", lessonId)
        .putString("lesson_title", lessonTitle)
        .apply()
}

fun clearContinueWatching(context: Context, lessonId: String) {
    val prefs = context.getSharedPreferences(CONTINUE_WATCHING_PREFS, Context.MODE_PRIVATE)
    if (prefs.getString("lesson_id", null) == lessonId) {
        prefs.edit().clear().apply()
    }
}

data class ContinueWatchingEntry(val lessonId: String, val lessonTitle: String)

fun getContinueWatching(context: Context): ContinueWatchingEntry? {
    val prefs = context.getSharedPreferences(CONTINUE_WATCHING_PREFS, Context.MODE_PRIVATE)
    val id = prefs.getString("lesson_id", null) ?: return null
    val title = prefs.getString("lesson_title", "") ?: ""
    return ContinueWatchingEntry(id, title)
}

/**
 * صورة مصغّرة للفيديو قبل التشغيل - من يوتيوب مباشرة (رابط ثابت معروف)،
 * أو من أول لقطة بالملف نفسه للفيديوهات المرفوعة مباشرة. فيميو غير مدعوم
 * حالياً (يحتاج نداء لـ API فيميو نفسه لجلب رابط الصورة، تحسين مستقبلي).
 */
@Composable
fun VideoThumbnail(url: String, modifier: Modifier = Modifier) {
    var bitmap by remember(url) { mutableStateOf<android.graphics.Bitmap?>(null) }
    var failed by remember(url) { mutableStateOf(false) }

    LaunchedEffect(url) {
        val result = withContext(Dispatchers.IO) {
            try {
                when (val source = resolveVideoSource(url)) {
                    is VideoSource.YouTube -> {
                        val videoId = source.embedUrl.substringAfterLast("/")
                        val thumbUrl = "https://img.youtube.com/vi/$videoId/hqdefault.jpg"
                        URL(thumbUrl).openStream().use { android.graphics.BitmapFactory.decodeStream(it) }
                    }
                    is VideoSource.DirectFile -> {
                        val retriever = android.media.MediaMetadataRetriever()
                        retriever.setDataSource(source.url, HashMap<String, String>())
                        val frame = retriever.getFrameAtTime(0)
                        retriever.release()
                        frame
                    }
                    else -> null // فيميو: غير مدعوم حالياً
                }
            } catch (e: Exception) {
                null
            }
        }
        if (result == null) failed = true else bitmap = result
    }

    val currentBitmap = bitmap
    if (currentBitmap != null) {
        androidx.compose.foundation.Image(
            bitmap = currentBitmap.asImageBitmap(),
            contentDescription = null,
            modifier = modifier,
            contentScale = androidx.compose.ui.layout.ContentScale.Crop
        )
    } else {
        Box(
            modifier = modifier.background(androidx.compose.ui.graphics.Color(0xFFDDD6CC)),
            contentAlignment = Alignment.Center
        ) {
            Text(if (failed) "🎬" else "…", style = MaterialTheme.typography.headlineSmall)
        }
    }
}

/**
 * مشغّل فيديو حقيقي داخل التطبيق - يدعم التحكم بالسرعة، التشغيل من نسخة
 * محلية إن وُجدت، استئناف آخر موضع مشاهدة، وتعليم الدرس مكتمل تلقائياً
 * عند وصول الفيديو للنهاية.
 */
@Composable
fun DirectVideoPlayer(
    url: String,
    contentId: String,
    lessonId: String,
    lessonTitle: String,
    captionUrl: String? = null,
    onVideoCompleted: (() -> Unit)? = null
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val localFile = remember { localVideoFile(context, contentId) }
    val hasLocalCopy = remember { mutableStateOf(localFile.exists()) }
    var downloading by remember { mutableStateOf(false) }
    var downloadProgress by remember { mutableStateOf(0) }
    var speed by remember { mutableStateOf(1f) }
    var isBuffering by remember { mutableStateOf(true) }
    var playbackError by remember { mutableStateOf<String?>(null) }
    var resumedFromMessage by remember { mutableStateOf<String?>(null) }

    SecureScreenWhileVisible()

    val playbackUrl = if (hasLocalCopy.value) localFile.toURI().toString() else url

    val exoPlayer = remember(playbackUrl) {
        ExoPlayer.Builder(context).build().apply {
            val mediaItem = if (captionUrl != null) {
                val subtitle = androidx.media3.common.MediaItem.SubtitleConfiguration.Builder(
                    android.net.Uri.parse(captionUrl)
                )
                    .setMimeType(androidx.media3.common.MimeTypes.TEXT_VTT)
                    .setLanguage("ar")
                    .build()
                MediaItem.Builder()
                    .setUri(playbackUrl)
                    .setSubtitleConfigurations(listOf(subtitle))
                    .build()
            } else {
                MediaItem.fromUri(playbackUrl)
            }
            setMediaItem(mediaItem)
            prepare()

            val savedPosition = getSavedPosition(context, contentId)
            if (savedPosition > 5000) { // نتجاهل أول 5 ثواني، ما يستاهل "استئناف" لهاي المدة القصيرة
                seekTo(savedPosition)
                resumedFromMessage = "تم الاستئناف من آخر موضع توقفت عنده"
            }

            playWhenReady = true
        }
    }

    DisposableEffect(exoPlayer) {
        val listener = object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                isBuffering = playbackState == Player.STATE_BUFFERING
                if (playbackState == Player.STATE_ENDED) {
                    clearSavedPosition(context, contentId)
                    clearContinueWatching(context, lessonId)
                    onVideoCompleted?.invoke()
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                playbackError = "تعذر تشغيل الفيديو: ${error.message ?: "خطأ غير معروف"}"
            }
        }
        exoPlayer.addListener(listener)
        onDispose { exoPlayer.removeListener(listener) }
    }

    LaunchedEffect(speed) {
        exoPlayer.setPlaybackSpeed(speed)
    }

    DisposableEffect(playbackUrl) {
        onDispose {
            // نحفظ موضع التوقف عند مغادرة الشاشة عشان يستأنف من نفس النقطة لاحقاً
            if (exoPlayer.duration > 0 && exoPlayer.currentPosition < exoPlayer.duration - 3000) {
                savePosition(context, contentId, exoPlayer.currentPosition)
                saveContinueWatching(context, lessonId, lessonTitle)
            } else {
                clearSavedPosition(context, contentId)
            }
            exoPlayer.release()
        }
    }

    Column {
        Box {
            AndroidView(
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(16f / 9f),
                factory = { PlayerView(context).apply { player = exoPlayer } }
            )

            if (isBuffering && playbackError == null) {
                Box(modifier = Modifier.matchParentSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }

            if (playbackError != null) {
                Box(
                    modifier = Modifier
                        .matchParentSize()
                        .padding(16.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(playbackError!!, color = androidx.compose.ui.graphics.Color.White)
                }
            }
        }

        resumedFromMessage?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth().padding(8.dp),
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            // التحكم بسرعة التشغيل
            Row {
                listOf(0.5f, 1f, 1.25f, 1.5f, 2f).forEach { s ->
                    TextButton(onClick = { speed = s }) {
                        Text(
                            "${s}x",
                            fontWeight = if (speed == s) androidx.compose.ui.text.font.FontWeight.Bold else null
                        )
                    }
                }
            }

            // تحميل للمشاهدة بدون إنترنت لاحقاً - يُحفظ داخل مساحة التطبيق الخاصة فقط
            if (!hasLocalCopy.value) {
                TextButton(
                    onClick = {
                        downloading = true
                        scope.launch {
                            try {
                                withContext(Dispatchers.IO) {
                                    val connection = URL(url).openConnection()
                                    val total = connection.contentLength
                                    connection.getInputStream().use { input ->
                                        localFile.outputStream().use { output ->
                                            val buffer = ByteArray(8 * 1024)
                                            var readBytes = 0
                                            var totalRead = 0L
                                            while (input.read(buffer).also { readBytes = it } != -1) {
                                                output.write(buffer, 0, readBytes)
                                                totalRead += readBytes
                                                if (total > 0) {
                                                    downloadProgress = ((totalRead * 100) / total).toInt()
                                                }
                                            }
                                        }
                                    }
                                }
                                hasLocalCopy.value = true
                            } catch (e: Exception) {
                                // فشل التحميل (مثلاً الرابط الموقّت انتهت صلاحيته) - نتجاهل بصمت
                                // ويقدر الطالب يعيد المحاولة من نفس الشاشة (رابط جديد يولّد تلقائياً)
                            } finally {
                                downloading = false
                            }
                        }
                    },
                    enabled = !downloading
                ) {
                    Text(if (downloading) "جاري التحميل $downloadProgress%" else "⬇ تحميل للمشاهدة بدون نت")
                }
            } else {
                Text("✅ محمّل", style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

/** تضمين مشغّل يوتيوب/فيميو الرسمي عبر WebView - نفس أسلوب أي موقع يضمّن فيديو خارجي */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun EmbeddedWebPlayer(embedUrl: String) {
    val context = LocalContext.current

    SecureScreenWhileVisible()

    AndroidView(
        modifier = Modifier
            .fillMaxWidth()
            .aspectRatio(16f / 9f),
        factory = {
            WebView(context).apply {
                settings.javaScriptEnabled = true
                settings.mediaPlaybackRequiresUserGesture = false
                loadUrl(embedUrl)
            }
        }
    )
}
