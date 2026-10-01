// Candidate B adapter (TurboModule NativeG1) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
package com.example.g1bench.g1native;

import com.facebook.react.BaseReactPackage;
import com.facebook.react.bridge.NativeModule;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.module.model.ReactModuleInfo;
import com.facebook.react.module.model.ReactModuleInfoProvider;

import java.util.HashMap;
import java.util.Map;

public final class G1NativePackage extends BaseReactPackage {
    @Override
    public NativeModule getModule(String name, ReactApplicationContext reactContext) {
        return NativeG1Spec.NAME.equals(name) ? new NativeG1Module(reactContext) : null;
    }

    @Override
    public ReactModuleInfoProvider getReactModuleInfoProvider() {
        return () -> {
            Map<String, ReactModuleInfo> map = new HashMap<>();
            map.put(NativeG1Spec.NAME, new ReactModuleInfo(NativeG1Spec.NAME, NativeG1Module.class.getName(), false, true, false, true));
            return map;
        };
    }
}
