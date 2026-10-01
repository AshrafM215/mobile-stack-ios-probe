// Candidate B adapter (TurboModule NativeG1) to the G1 common native module - NON-PRODUCTION / SYNTHETIC DATA ONLY.
#import <G1NativeSpec/G1NativeSpec.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted by the app delegate with an NSURL "g1bench-b://cmd?name=...&args=..." for a running app (lab hook transport).
extern NSString *const G1LabCommandURLNotification;

@interface RCTNativeG1 : NativeG1SpecBase <NativeG1Spec>
@end

NS_ASSUME_NONNULL_END
