// G1 synthetic native bridge - NON-PRODUCTION / SYNTHETIC DATA ONLY.
#import "RCTNativeG1Ar.h"

#import <ARKit/ARKit.h>

@implementation RCTNativeG1Ar

+ (NSString *)moduleName
{
  return @"NativeG1Ar";
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeG1ArSpecJSI>(params);
}

- (NSNumber *)isSupported
{
  BOOL supported = [ARWorldTrackingConfiguration isSupported];
  NSLog(@"G1_PROBE app=candidate-b-react-native platform=ios event=native_ar_check supported=%d", supported ? 1 : 0);
  return @(supported);
}

@end
