// Candidate A adapter to the G1 common native module (Android) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
package com.example.g1bench.g1native

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.example.g1bench.common.BridgeWorker
import com.example.g1bench.common.G1Native
import com.example.g1bench.common.LabCommand
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Platform-channel adapter (MethodChannel "g1/native", EventChannels "g1/events" and "g1/n2r"). Every call is validated
 * before it reaches the common module: wrong argument types -> BAD_ARGUMENT, any string or byte field above 64 KiB ->
 * PAYLOAD_TOO_LARGE, unknown method -> notImplemented. Results are always delivered on the platform (main) thread.
 */
class G1NativePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware, PluginRegistry.NewIntentListener {
    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var n2r: EventChannel
    private val main = Handler(Looper.getMainLooper())
    private var activity: Activity? = null
    private var binding: ActivityPluginBinding? = null
    private var eventSink: EventChannel.EventSink? = null
    private var n2rSink: EventChannel.EventSink? = null
    private val pendingEvents = ArrayList<Map<String, Any?>>()
    private var launchCommand: Map<String, Any?>? = null

    override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
        G1Native.init(b.applicationContext, "A")
        channel = MethodChannel(b.binaryMessenger, "g1/native")
        channel.setMethodCallHandler(this)
        events = EventChannel(b.binaryMessenger, "g1/events")
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                eventSink = sink
                pendingEvents.forEach { sink.success(it) }
                pendingEvents.clear()
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        n2r = EventChannel(b.binaryMessenger, "g1/n2r")
        n2r.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                n2rSink = sink
            }

            override fun onCancel(arguments: Any?) {
                n2rSink = null
            }
        })
    }

    override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        n2r.setStreamHandler(null)
    }

    // ---------------- activity and lab commands ----------------

    private fun attach(b: ActivityPluginBinding) {
        binding = b
        activity = b.activity
        b.addOnNewIntentListener(this)
        if (launchCommand == null) launchCommand = commandOf(b.activity.intent)
    }

    private fun detach() {
        binding?.removeOnNewIntentListener(this)
        binding = null
        activity = null
    }

    override fun onAttachedToActivity(b: ActivityPluginBinding) = attach(b)
    override fun onDetachedFromActivityForConfigChanges() = detach()
    override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) = attach(b)
    override fun onDetachedFromActivity() = detach()

    private fun commandOf(intent: Intent?): Map<String, Any?>? {
        val cmd = LabCommand.fromIntent(intent) ?: return null
        return mapOf("name" to cmd.name, "args" to cmd.argsJson)
    }

    override fun onNewIntent(intent: Intent): Boolean {
        val cmd = commandOf(intent) ?: return false
        emit(mapOf("type" to "command") + cmd)
        return true
    }

    private fun emit(event: Map<String, Any?>) {
        main.post {
            val sink = eventSink
            if (sink != null) sink.success(event) else pendingEvents.add(event)
        }
    }

    // ---------------- argument checks ----------------

    private class BadArgument(val code: String, message: String) : Exception(message)

    private fun str(call: MethodCall, key: String, optional: Boolean = false): String? {
        val v = call.argument<Any?>(key)
        if (v == null) {
            if (optional) return null
            throw BadArgument("BAD_ARGUMENT", "$key missing")
        }
        if (v !is String) throw BadArgument("BAD_ARGUMENT", "$key must be a string")
        if (v.length > MAX_FIELD) throw BadArgument("PAYLOAD_TOO_LARGE", "$key too large")
        return v
    }

    private fun bytes(call: MethodCall, key: String): ByteArray {
        val v = call.argument<Any?>(key) as? ByteArray ?: throw BadArgument("BAD_ARGUMENT", "$key must be bytes")
        if (v.size > MAX_FIELD) throw BadArgument("PAYLOAD_TOO_LARGE", "$key too large")
        return v
    }

    private fun int(call: MethodCall, key: String): Int =
        (call.argument<Any?>(key) as? Number)?.toInt() ?: throw BadArgument("BAD_ARGUMENT", "$key must be a number")

    private fun long(call: MethodCall, key: String): Long =
        (call.argument<Any?>(key) as? Number)?.toLong() ?: throw BadArgument("BAD_ARGUMENT", "$key must be a number")

    private fun bool(call: MethodCall, key: String): Boolean =
        call.argument<Any?>(key) as? Boolean ?: throw BadArgument("BAD_ARGUMENT", "$key must be a boolean")

    private fun onMain(block: () -> Unit) = main.post(block)

    // ---------------- dispatch ----------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            dispatch(call, result)
        } catch (e: BadArgument) {
            result.error(e.code, e.message, null)
        } catch (e: java.io.IOException) {
            result.error("IO", e.javaClass.simpleName, null)
        }
    }

    private fun dispatch(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "nowNanos" -> result.success(G1Native.nowNanos())
            "mark" -> {
                @Suppress("UNCHECKED_CAST")
                val kv = (call.argument<Any?>("kv") as? List<Any?>)?.map { it as? String ?: throw BadArgument("BAD_ARGUMENT", "kv") }
                    ?: emptyList()
                G1Native.mark(str(call, "name")!!, long(call, "rt"), *kv.toTypedArray())
                result.success(null)
            }
            "reportReady" -> {
                val a = activity ?: throw BadArgument("BAD_ARGUMENT", "no activity")
                G1Native.reportReady(a, long(call, "rt"))
                result.success(null)
            }
            "reportResumeReady" -> {
                G1Native.reportResumeReady(long(call, "rt"))
                result.success(null)
            }
            "ensureBundle" -> result.success(G1Native.ensureBundle())
            "bundleInfo" -> result.success(G1Native.bundleInfo())
            "importBundleFile" -> result.success(G1Native.importBundleFile(str(call, "name")))
            "importBundleBytes" -> {
                val zip = call.argument<Any?>("bytes") as? ByteArray ?: throw BadArgument("BAD_ARGUMENT", "bytes")
                if (zip.size > MAX_BUNDLE) throw BadArgument("PAYLOAD_TOO_LARGE", "bundle too large")
                result.success(G1Native.importBundleBytes(zip, str(call, "source")))
            }
            "rollback" -> result.success(G1Native.rollback())
            "readBundleFile" -> result.success(G1Native.readBundleFile(str(call, "path")))
            "validateQr" -> result.success(G1Native.validateQr(str(call, "payload", optional = true)))
            "decodeQrImport" -> result.success(G1Native.decodeQrImport(str(call, "name")))
            "scanQr" -> {
                val a = activity ?: throw BadArgument("BAD_ARGUMENT", "no activity")
                G1Native.startQrScanner(a, str(call, "requestId")) { payload, error ->
                    onMain { result.success(mapOf("payload" to payload, "error" to error)) }
                }
            }
            "arAvailability" -> result.success(G1Native.arAvailability())
            "startAr" -> {
                val a = activity ?: throw BadArgument("BAD_ARGUMENT", "no activity")
                val requestId = str(call, "requestId")!!
                G1Native.startAr(a, requestId, str(call, "script", optional = true), str(call, "texts", optional = true)) { id, json ->
                    emit(mapOf("type" to "ar", "requestId" to id, "event" to json))
                }
                result.success(null)
            }
            "closeAr" -> {
                G1Native.closeAr(str(call, "requestId"))
                result.success(null)
            }
            "setArGuidance" -> {
                G1Native.setArGuidance(str(call, "requestId"), bool(call, "allowed"))
                result.success(null)
            }
            "payloadBlock" -> result.success(G1Native.payloadBlock())
            "echoAsync" -> {
                val payload = bytes(call, "payload")
                G1Native.echoAsync(payload) { r, entry -> onMain { result.success(longArrayOf(r, entry)) } }
            }
            "startN2R" -> {
                val size = int(call, "size")
                val count = int(call, "count")
                val rate = int(call, "rateHz")
                G1Native.startN2R(size, count, rate, object : BridgeWorker.N2RSink {
                    override fun onMessage(seq: Int, sentNanos: Long, payload: ByteArray) {
                        onMain { n2rSink?.success(mapOf("seq" to seq, "sent" to sentNanos, "payload" to payload)) }
                    }

                    override fun onDone(sent: Int, dropped: Int) {
                        onMain { n2rSink?.success(mapOf("done" to true, "sent" to sent, "dropped" to dropped)) }
                    }
                })
                result.success(null)
            }
            "sessionStart" -> result.success(G1Native.sessionStart(str(call, "marker")))
            "sessionActive" -> result.success(G1Native.sessionActive())
            "sessionEnd" -> {
                G1Native.sessionEnd()
                result.success(null)
            }
            "crash" -> {
                G1Native.crash(str(call, "case"))
                result.success(null)
            }
            "writeOut" -> result.success(G1Native.writeOut(str(call, "name"), str(call, "text")!!))
            "readImportText" -> result.success(G1Native.readImportText(str(call, "name")))
            "labCa" -> result.success(G1Native.labCa())
            "readImportBytes" -> result.success(G1Native.readImportBytes(str(call, "name")))
            "launchCommand" -> {
                val c = launchCommand
                launchCommand = null
                result.success(c)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val MAX_FIELD = 64 * 1024
        const val MAX_BUNDLE = 64 * 1024 * 1024
    }
}
