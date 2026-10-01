// Candidate B adapter (TurboModule NativeG1) to the G1 common native module - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// On Android the generated JSI layer rejects a wrong argument type with a JavaScript error before any native code runs;
// on iOS the ObjC TurboModule layer passes the converted JavaScript value through unchecked, so every object argument is
// checked here (BAD_ARGUMENT). Sizes are checked on both platforms (PAYLOAD_TOO_LARGE). Primitive (BOOL/double)
// arguments cannot be checked on iOS: the invocation receives the raw converted value.
#import "RCTNativeG1.h"

// The generated Swift header names ARKit, AVFoundation and CoreMedia types; its own "@import" lines are skipped in
// Objective-C++ (no C++ modules), so the frameworks are imported explicitly before it.
#import <ARKit/ARKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

#if __has_include(<G1NativeCommon/G1NativeCommon-Swift.h>)
#import <G1NativeCommon/G1NativeCommon-Swift.h>
#else
#import "G1NativeCommon-Swift.h"
#endif

NSString *const G1LabCommandURLNotification = @"G1LabCommandURL";

static const NSUInteger kMaxField = 64 * 1024;
static const NSUInteger kMaxB64 = (64 * 1024 + 2) / 3 * 4;
static const NSUInteger kMaxBundleB64 = (64 * 1024 * 1024 + 2) / 3 * 4;

@implementation RCTNativeG1 {
  BOOL _launchConsumed;
  BOOL _observingLabUrls;
}

RCT_EXPORT_MODULE(NativeG1)

+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

- (instancetype)init
{
  if (self = [super init]) {
    [G1NativeBridge initializeWithAppId:@"B"];
  }
  return self;
}

// Only the instance connected to the JavaScript runtime (event emitter callback set) observes lab URLs. Emitting
// through an instance without the callback aborts the process (std::bad_function_call in the generated emitter), which
// is what the first iOS probe of qr.inject over the lab URL showed.
- (void)setEventEmitterCallback:(EventEmitterCallbackWrapper *)eventEmitterCallbackWrapper
{
  [super setEventEmitterCallback:eventEmitterCallbackWrapper];
  if (!_observingLabUrls && _eventEmitterCallback) {
    _observingLabUrls = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onLabUrl:)
                                                 name:G1LabCommandURLNotification
                                               object:nil];
  }
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)onLabUrl:(NSNotification *)notification
{
  NSURL *url = notification.object;
  if (![url isKindOfClass:[NSURL class]] || !_eventEmitterCallback) {
    return;
  }
  NSArray<NSString *> *cmd = [G1NativeBridge urlCommand:url];
  if (cmd.count == 2) {
    [self emitOnCommand:@{@"name" : cmd[0], @"args" : cmd[1]}];
  }
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeG1SpecJSI>(params);
}

static NSData *_Nullable G1Base64(NSString *s)
{
  return [[NSData alloc] initWithBase64EncodedString:s options:0];
}

static BOOL G1Str(id v)
{
  return [v isKindOfClass:[NSString class]];
}

/// nil / NSNull (JavaScript null) or a string
static BOOL G1OptStr(id v)
{
  return v == nil || v == (id)kCFNull || [v isKindOfClass:[NSString class]];
}

static NSString *_Nullable G1NullToNil(id v)
{
  return v == (id)kCFNull ? nil : v;
}

#define G1_REJECT_BAD_ARGUMENT                \
  do {                                        \
    reject(@"BAD_ARGUMENT", @"argument", nil); \
    return;                                   \
  } while (0)

// ---------------- synchronous (JSI) ----------------

- (NSNumber *)nowNanos
{
  return @([G1NativeBridge nowNanos]);
}

- (NSArray<NSNumber *> *)echoSyncBase64:(NSString *)payload
{
  if (!G1Str(payload) || payload.length > kMaxB64 || G1Base64(payload) == nil) {
    return @[]; // rejected (PAYLOAD_TOO_LARGE / BAD_ARGUMENT)
  }
  return [G1NativeBridge echoSyncBase64:payload];
}

// ---------------- markers and readiness ----------------

- (void)mark:(NSString *)name rt:(double)rt kv:(NSArray *)kv
{
  if (!G1Str(name) || ![kv isKindOfClass:[NSArray class]]) {
    return;
  }
  NSMutableArray<NSString *> *fields = [NSMutableArray arrayWithCapacity:kv.count];
  for (id v in kv) {
    if ([v isKindOfClass:[NSString class]]) {
      [fields addObject:v];
    }
  }
  [G1NativeBridge mark:name runtimeNanos:rt kv:fields];
}

- (void)reportReady:(double)rt
{
  [G1NativeBridge reportReady:rt];
}

- (void)reportResumeReady:(double)rt
{
  [G1NativeBridge reportResumeReady:rt];
}

// ---------------- bundle ----------------

- (void)ensureBundle:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  resolve([G1NativeBridge ensureBundle]);
}

- (void)bundleInfo:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  resolve([G1NativeBridge bundleInfo]);
}

- (void)bundleDirectoryUrl:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  resolve([G1NativeBridge bundleDirectoryUrl]);
}

- (void)readBundleFile:(NSString *)path resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  if (!G1Str(path)) G1_REJECT_BAD_ARGUMENT;
  NSString *text = [G1NativeBridge readBundleFile:path];
  if (text == nil) {
    reject(@"IO", @"not available", nil);
  } else {
    resolve(text);
  }
}

- (void)importBundleFile:(NSString *)name resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  if (!G1Str(name)) G1_REJECT_BAD_ARGUMENT;
  resolve([G1NativeBridge importBundleFile:name]);
}

- (void)importBundleBase64:(NSString *)zip
                    source:(NSString *)source
                   resolve:(RCTPromiseResolveBlock)resolve
                    reject:(RCTPromiseRejectBlock)reject
{
  if (!G1Str(zip) || !G1Str(source)) G1_REJECT_BAD_ARGUMENT;
  if (zip.length > kMaxBundleB64 || source.length > kMaxField) {
    reject(@"PAYLOAD_TOO_LARGE", @"too large", nil);
    return;
  }
  if (G1Base64(zip) == nil) {
    reject(@"BAD_ARGUMENT", @"base64", nil);
    return;
  }
  resolve([G1NativeBridge importBundleBase64:zip source:source]);
}

- (void)rollback:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  resolve([G1NativeBridge rollback]);
}

// ---------------- QR ----------------

- (void)validateQr:(NSString *_Nullable)payload resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  if (!G1OptStr(payload)) G1_REJECT_BAD_ARGUMENT;
  payload = G1NullToNil(payload);
  if (payload.length > kMaxField) {
    reject(@"PAYLOAD_TOO_LARGE", @"too large", nil);
    return;
  }
  resolve([G1NativeBridge validateQr:payload]);
}

- (void)decodeQrImport:(NSString *)name resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  if (!G1Str(name)) G1_REJECT_BAD_ARGUMENT;
  resolve([G1NativeBridge decodeQrImport:name] ?: (id)[NSNull null]);
}

- (void)scanQr:(NSString *)requestId resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  if (!G1Str(requestId)) G1_REJECT_BAD_ARGUMENT;
  [G1NativeBridge startQrScanner:requestId
                        callback:^(NSString *_Nullable payload, NSString *_Nullable error) {
                          NSDictionary *result = @{
                            @"payload" : payload ?: (id)[NSNull null],
                            @"error" : error ?: (id)[NSNull null],
                          };
                          NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
                          resolve([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]);
                        }];
}

// ---------------- AR ----------------

- (void)arAvailability:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  resolve([G1NativeBridge arAvailability]);
}

- (void)startAr:(NSString *)requestId script:(NSString *_Nullable)script texts:(NSString *)texts
{
  if (!G1Str(requestId) || !G1OptStr(script) || !G1Str(texts)) {
    return;
  }
  script = G1NullToNil(script);
  __weak RCTNativeG1 *weakSelf = self;
  [G1NativeBridge startAr:requestId
                   script:script
                    texts:texts
                 listener:^(NSString *eventRequestId, NSString *json) {
                   [weakSelf emitOnArEvent:@{@"requestId" : eventRequestId, @"event" : json}];
                 }];
}

- (void)setArGuidance:(NSString *)requestId allowed:(BOOL)allowed
{
  if (!G1Str(requestId)) {
    return;
  }
  [G1NativeBridge setArGuidance:requestId allowed:allowed];
}

- (void)closeAr:(NSString *)requestId
{
  if (!G1Str(requestId)) {
    return;
  }
  [G1NativeBridge closeAr:requestId];
}

// ---------------- bridge workload ----------------

- (void)payloadBlockBase64:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  resolve([G1NativeBridge payloadBlockBase64]);
}

- (void)echoAsyncBase64:(NSString *)payload resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  if (!G1Str(payload)) G1_REJECT_BAD_ARGUMENT;
  if (payload.length > kMaxB64) {
    reject(@"PAYLOAD_TOO_LARGE", @"too large", nil);
    return;
  }
  if (G1Base64(payload) == nil) {
    reject(@"BAD_ARGUMENT", @"base64", nil);
    return;
  }
  [G1NativeBridge echoAsyncBase64:payload
                         callback:^(double result, double entry) {
                           resolve(@[ @(result), @(entry) ]);
                         }];
}

- (void)startN2R:(double)size count:(double)count rateHz:(double)rateHz
{
  __weak RCTNativeG1 *weakSelf = self;
  [G1NativeBridge startN2RWithSize:(NSInteger)size
                             count:(NSInteger)count
                            rateHz:(NSInteger)rateHz
                         onMessage:^(NSInteger seq, double sent, NSString *payload) {
                           [weakSelf emitOnN2R:@{
                             @"seq" : @(seq),
                             @"sent" : @(sent),
                             @"payload" : payload,
                             @"done" : @NO,
                             @"count" : @0
                           }];
                         }
                            onDone:^(NSInteger sent, NSInteger dropped) {
                              [weakSelf emitOnN2R:@{
                                @"seq" : @(-1),
                                @"sent" : @0,
                                @"payload" : @"",
                                @"done" : @YES,
                                @"count" : @(sent)
                              }];
                            }];
}

// ---------------- session, crash, files ----------------

- (void)sessionStart:(NSString *)marker resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  if (!G1Str(marker)) G1_REJECT_BAD_ARGUMENT;
  resolve(@([G1NativeBridge sessionStart:marker]));
}

- (void)sessionActive:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  resolve(@([G1NativeBridge sessionActive]));
}

- (void)sessionEnd:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  [G1NativeBridge sessionEnd];
  resolve(nil);
}

- (void)crash:(NSString *)caseId
{
  if (!G1Str(caseId)) {
    return;
  }
  [G1NativeBridge crash:caseId];
}

- (void)writeOut:(NSString *)name text:(NSString *)text resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  if (!G1Str(name) || !G1Str(text)) G1_REJECT_BAD_ARGUMENT;
  NSString *sha = [G1NativeBridge writeOut:name text:text];
  if (sha == nil) {
    reject(@"IO", @"write failed", nil);
  } else {
    resolve(sha);
  }
}

- (void)readImportText:(NSString *)name resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  if (!G1Str(name)) G1_REJECT_BAD_ARGUMENT;
  NSString *text = [G1NativeBridge readImportText:name];
  if (text == nil) {
    reject(@"IO", @"read failed", nil);
  } else {
    resolve(text);
  }
}

- (void)readImportBase64:(NSString *)name resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  if (!G1Str(name)) G1_REJECT_BAD_ARGUMENT;
  NSString *b64 = [G1NativeBridge readImportBase64:name];
  if (b64 == nil) {
    reject(@"IO", @"read failed", nil);
  } else {
    resolve(b64);
  }
}

- (void)launchCommand:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject
{
  if (_launchConsumed) {
    resolve([NSNull null]);
    return;
  }
  _launchConsumed = YES;
  NSArray<NSString *> *cmd = [G1NativeBridge launchCommand];
  if (cmd.count != 2) {
    resolve([NSNull null]);
    return;
  }
  NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"name" : cmd[0], @"args" : cmd[1]} options:0 error:nil];
  resolve([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]);
}

@end
