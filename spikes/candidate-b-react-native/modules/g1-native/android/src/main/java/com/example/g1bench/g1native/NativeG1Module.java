// Candidate B adapter (TurboModule NativeG1) to the G1 common native module - NON-PRODUCTION / SYNTHETIC DATA ONLY.
package com.example.g1bench.g1native;

import android.app.Activity;
import android.content.Intent;
import android.util.Base64;

import com.example.g1bench.common.BridgeWorker;
import com.example.g1bench.common.G1Native;
import com.example.g1bench.common.LabCommand;
import com.facebook.react.bridge.ActivityEventListener;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReadableArray;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * TurboModule NativeG1 (JSI). Argument types are enforced by the generated JSI layer (a wrong type is a JavaScript
 * TypeError before any native code runs); sizes are checked here: any string field above 64 KiB (base64 payloads above
 * the encoded size of 64 KiB) is rejected with PAYLOAD_TOO_LARGE, undecodable base64 with BAD_ARGUMENT.
 */
public final class NativeG1Module extends NativeG1Spec implements ActivityEventListener {
    static final int MAX_FIELD = 64 * 1024;
    static final int MAX_B64 = (64 * 1024 + 2) / 3 * 4;
    static final int MAX_BUNDLE_B64 = (64 * 1024 * 1024 + 2) / 3 * 4;

    private boolean launchConsumed;

    public NativeG1Module(ReactApplicationContext context) {
        super(context);
        G1Native.init(context, "B");
        context.addActivityEventListener(this);
    }

    private Activity activity() { return getReactApplicationContext().getCurrentActivity(); }

    private static boolean tooLarge(String s, int limit) { return s != null && s.length() > limit; }

    private static byte[] base64(String s) {
        try {
            return Base64.decode(s, Base64.NO_WRAP);
        } catch (IllegalArgumentException e) {
            return null;
        }
    }

    private static WritableMap commandMap(LabCommand c) {
        WritableMap m = Arguments.createMap();
        m.putString("name", c.name);
        m.putString("args", c.argsJson);
        return m;
    }

    // ---------------- lab commands ----------------

    @Override
    public void onNewIntent(Intent intent) {
        LabCommand c = LabCommand.fromIntent(intent);
        if (c != null) emitOnCommand(commandMap(c));
    }

    @Override
    public void onActivityResult(Activity activity, int requestCode, int resultCode, Intent data) {}

    @Override
    public void launchCommand(Promise promise) {
        if (launchConsumed) {
            promise.resolve(null);
            return;
        }
        launchConsumed = true;
        Activity a = activity();
        LabCommand c = a == null ? null : LabCommand.fromIntent(a.getIntent());
        if (c == null) {
            promise.resolve(null);
            return;
        }
        try {
            promise.resolve(new JSONObject().put("name", c.name).put("args", c.argsJson).toString());
        } catch (JSONException e) {
            promise.reject("IO", e);
        }
    }

    // ---------------- synchronous (JSI) ----------------

    @Override
    public double nowNanos() { return (double) G1Native.nowNanos(); }

    @Override
    public WritableArray echoSyncBase64(String payload) {
        WritableArray out = Arguments.createArray();
        byte[] bytes = tooLarge(payload, MAX_B64) ? null : base64(payload);
        if (bytes == null) return out; // empty array = rejected (PAYLOAD_TOO_LARGE / BAD_ARGUMENT)
        long[] r = G1Native.echoSync(bytes);
        out.pushDouble((double) r[0]);
        out.pushDouble((double) r[1]);
        return out;
    }

    // ---------------- markers and readiness ----------------

    @Override
    public void mark(String name, double rt, ReadableArray kv) {
        String[] fields = new String[kv.size()];
        for (int i = 0; i < fields.length; i++) fields[i] = kv.getString(i);
        G1Native.mark(name, (long) rt, fields);
    }

    @Override
    public void reportReady(double rt) {
        Activity a = activity();
        if (a != null) G1Native.reportReady(a, (long) rt);
    }

    @Override
    public void reportResumeReady(double rt) { G1Native.reportResumeReady((long) rt); }

    // ---------------- bundle ----------------

    @Override
    public void ensureBundle(Promise promise) { promise.resolve(G1Native.ensureBundle()); }

    @Override
    public void bundleInfo(Promise promise) { promise.resolve(G1Native.bundleInfo()); }

    @Override
    public void bundleDirectoryUrl(Promise promise) {
        try {
            JSONObject info = new JSONObject(G1Native.bundleInfo());
            String dir = info.optString("dir", "");
            promise.resolve(info.isNull("dir") || dir.isEmpty() ? null : "file://" + dir + "/");
        } catch (JSONException e) {
            promise.reject("IO", e);
        }
    }

    @Override
    public void readBundleFile(String path, Promise promise) {
        try {
            promise.resolve(G1Native.readBundleFile(path));
        } catch (java.io.IOException e) {
            promise.reject("IO", e.getClass().getSimpleName());
        }
    }

    @Override
    public void importBundleFile(String name, Promise promise) { promise.resolve(G1Native.importBundleFile(name)); }

    @Override
    public void importBundleBase64(String zip, String source, Promise promise) {
        if (tooLarge(zip, MAX_BUNDLE_B64) || tooLarge(source, MAX_FIELD)) {
            promise.reject("PAYLOAD_TOO_LARGE", "too large");
            return;
        }
        byte[] bytes = base64(zip);
        if (bytes == null) {
            promise.reject("BAD_ARGUMENT", "base64");
            return;
        }
        promise.resolve(G1Native.importBundleBytes(bytes, source));
    }

    @Override
    public void rollback(Promise promise) { promise.resolve(G1Native.rollback()); }

    @Override
    public void removeBundles(Promise promise) { promise.resolve(G1Native.removeBundles()); }

    // ---------------- QR ----------------

    @Override
    public void validateQr(String payload, Promise promise) {
        if (tooLarge(payload, MAX_FIELD)) {
            promise.reject("PAYLOAD_TOO_LARGE", "too large");
            return;
        }
        promise.resolve(G1Native.validateQr(payload));
    }

    @Override
    public void decodeQrImport(String name, Promise promise) { promise.resolve(G1Native.decodeQrImport(name)); }

    @Override
    public void scanQr(String requestId, Promise promise) {
        Activity a = activity();
        if (a == null) {
            promise.resolve("{\"payload\":null,\"error\":\"CAMERA_UNAVAILABLE\"}");
            return;
        }
        G1Native.startQrScanner(a, requestId, (payload, error) -> {
            try {
                promise.resolve(new JSONObject().put("payload", payload == null ? JSONObject.NULL : payload)
                        .put("error", error == null ? JSONObject.NULL : error).toString());
            } catch (JSONException e) {
                promise.reject("IO", e);
            }
        });
    }

    // ---------------- AR ----------------

    @Override
    public void arAvailability(Promise promise) { promise.resolve(G1Native.arAvailability()); }

    @Override
    public void startAr(String requestId, String script, String texts) {
        Activity a = activity();
        if (a == null) return;
        G1Native.startAr(a, requestId, script, texts, (id, json) -> {
            WritableMap m = Arguments.createMap();
            m.putString("requestId", id);
            m.putString("event", json);
            emitOnArEvent(m);
        });
    }

    @Override
    public void setArGuidance(String requestId, boolean allowed) { G1Native.setArGuidance(requestId, allowed); }

    @Override
    public void closeAr(String requestId) { G1Native.closeAr(requestId); }

    // ---------------- bridge workload ----------------

    @Override
    public void payloadBlockBase64(Promise promise) {
        promise.resolve(Base64.encodeToString(G1Native.payloadBlock(), Base64.NO_WRAP));
    }

    @Override
    public void echoAsyncBase64(String payload, Promise promise) {
        if (tooLarge(payload, MAX_B64)) {
            promise.reject("PAYLOAD_TOO_LARGE", "too large");
            return;
        }
        byte[] bytes = base64(payload);
        if (bytes == null) {
            promise.reject("BAD_ARGUMENT", "base64");
            return;
        }
        G1Native.echoAsync(bytes, (r, entry) -> {
            WritableArray out = Arguments.createArray();
            out.pushDouble((double) r);
            out.pushDouble((double) entry);
            promise.resolve(out);
        });
    }

    @Override
    public void startN2R(double size, double count, double rateHz) {
        G1Native.startN2R((int) size, (int) count, (int) rateHz, new BridgeWorker.N2RSink() {
            @Override
            public void onMessage(int seq, long sentNanos, byte[] payload) {
                WritableMap m = Arguments.createMap();
                m.putInt("seq", seq);
                m.putDouble("sent", (double) sentNanos);
                m.putString("payload", Base64.encodeToString(payload, Base64.NO_WRAP));
                m.putBoolean("done", false);
                m.putInt("count", 0);
                emitOnN2R(m);
            }

            @Override
            public void onDone(int sent, int dropped) {
                WritableMap m = Arguments.createMap();
                m.putInt("seq", -1);
                m.putDouble("sent", 0);
                m.putString("payload", "");
                m.putBoolean("done", true);
                m.putInt("count", sent);
                emitOnN2R(m);
            }
        });
    }

    // ---------------- session, crash, files ----------------

    @Override
    public void sessionStart(String marker, Promise promise) { promise.resolve(G1Native.sessionStart(marker)); }

    @Override
    public void sessionActive(Promise promise) { promise.resolve(G1Native.sessionActive()); }

    @Override
    public void sessionEnd(Promise promise) {
        G1Native.sessionEnd();
        promise.resolve(null);
    }

    @Override
    public void crash(String caseId) { G1Native.crash(caseId); }

    @Override
    public void writeOut(String name, String text, Promise promise) {
        try {
            promise.resolve(G1Native.writeOut(name, text));
        } catch (java.io.IOException e) {
            promise.reject("IO", e.getClass().getSimpleName());
        }
    }

    @Override
    public void readImportText(String name, Promise promise) {
        try {
            promise.resolve(G1Native.readImportText(name));
        } catch (java.io.IOException e) {
            promise.reject("IO", e.getClass().getSimpleName());
        }
    }

    @Override
    public void readImportBase64(String name, Promise promise) {
        try {
            promise.resolve(Base64.encodeToString(G1Native.readImportBytes(name), Base64.NO_WRAP));
        } catch (java.io.IOException e) {
            promise.reject("IO", e.getClass().getSimpleName());
        }
    }
}
