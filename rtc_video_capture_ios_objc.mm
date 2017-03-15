/*
 *  Copyright (c) 2013 The WebRTC project authors. All Rights Reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

#import <UIKit/UIKit.h>

#import "webrtc/modules/video_capture/ios/device_info_ios_objc.h"
#import "webrtc/modules/video_capture/ios/rtc_video_capture_ios_objc.h"

#include "webrtc/system_wrappers/interface/trace.h"
#import"filter_manage.h"

using namespace webrtc;
using namespace webrtc::videocapturemodule;


@interface RTCVideoCaptureIosObjC (hidden)
- (int)changeCaptureInputWithName:(NSString*)captureDeviceName;
@end

@implementation RTCVideoCaptureIosObjC {
  webrtc::videocapturemodule::VideoCaptureIos* _owner;
  webrtc::VideoCaptureCapability _capability;
  AVCaptureSession* _captureSession;
    AVCaptureDevicePosition _position;
  int _captureId;
  AVCaptureConnection* _connection;
  BOOL _captureChanging;  // Guarded by _captureChangingCondition.
  NSCondition* _captureChangingCondition;
}

@synthesize frameRotation = _framRotation;
@synthesize filter_type=_filter_type;
//@synthesize filter_sensity=_filter_sensity;

- (id)initWithOwner:(VideoCaptureIos*)owner captureId:(int)captureId {
  _filter_type=-1;
  if (self == [super init]) {
    _owner = owner;
    _captureId = captureId;
    _captureSession = [[AVCaptureSession alloc] init];
#if defined(__IPHONE_7_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_7_0
    NSString* version = [[UIDevice currentDevice] systemVersion];
    if ([version integerValue] >= 7) {
      _captureSession.usesApplicationAudioSession = NO;
    }
#endif
    _captureChanging = NO;
    
    _captureChangingCondition = [[NSCondition alloc] init];

    if (!_captureSession || !_captureChangingCondition) {
      return nil;
    }

    // create and configure a new output (using callbacks)
    AVCaptureVideoDataOutput* captureOutput =
        [[AVCaptureVideoDataOutput alloc] init];
    NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;

      NSNumber* val = [NSNumber
                       numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
//    NSNumber* val = [NSNumber
//        numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange];
    NSDictionary* videoSettings =
        [NSDictionary dictionaryWithObject:val forKey:key];
    captureOutput.videoSettings = videoSettings;

    // add new output
    if ([_captureSession canAddOutput:captureOutput]) {
      [_captureSession addOutput:captureOutput];
    } else {
      WEBRTC_TRACE(kTraceError,
                   kTraceVideoCapture,
                   _captureId,
                   "%s:%s:%d Could not add output to AVCaptureSession ",
                   __FILE__,
                   __FUNCTION__,
                   __LINE__);
    }

    NSNotificationCenter* notify = [NSNotificationCenter defaultCenter];
    [notify addObserver:self
               selector:@selector(onVideoError:)
                   name:AVCaptureSessionRuntimeErrorNotification
                 object:_captureSession];
      
    [notify addObserver:self
               selector:@selector(statusBarOrientationDidChange:)
                   name:@"StatusBarOrientationDidChange"
                 object:nil];
  }

  return self;
}

- (void)directOutputToSelf {
  [[self currentOutput]
      setSampleBufferDelegate:self
                        queue:dispatch_get_global_queue(
                                  DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
}

- (void)directOutputToNil {
  [[self currentOutput] setSampleBufferDelegate:nil queue:NULL];
}

- (void)statusBarOrientationDidChange:(NSNotification*)notification {
  [self setRelativeVideoOrientation];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)setCaptureDeviceByUniqueId:(NSString*)uniqueId {
  [self waitForCaptureChangeToFinish];
  // check to see if the camera is already set
  if (_captureSession) {
    NSArray* currentInputs = [NSArray arrayWithArray:[_captureSession inputs]];
    if ([currentInputs count] > 0) {
      AVCaptureDeviceInput* currentInput = [currentInputs objectAtIndex:0];
      if ([uniqueId isEqualToString:[currentInput.device localizedName]]) {
        return YES;
      }
    }
  }

  return [self changeCaptureInputByUniqueId:uniqueId];
}

- (BOOL)startCaptureWithCapability:(const VideoCaptureCapability&)capability {
  [self waitForCaptureChangeToFinish];
  if (!_captureSession) {
    return NO;
  }

  // check limits of the resolution
  if (capability.maxFPS < 0 || capability.maxFPS > 60) {
    return NO;
  }

  if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset1920x1080]) {
    if (capability.width > 1920 || capability.height > 1080) {
      return NO;
    }
  } else if ([_captureSession
                 canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
    if (capability.width > 1280 || capability.height > 720) {
      return NO;
    }
  } else if ([_captureSession
                 canSetSessionPreset:AVCaptureSessionPreset640x480]) {
    if (capability.width > 640 || capability.height > 480) {
      return NO;
    }
  } else if ([_captureSession
                 canSetSessionPreset:AVCaptureSessionPreset352x288]) {
    if (capability.width > 352 || capability.height > 288) {
      return NO;
    }
  } else if (capability.width < 0 || capability.height < 0) {
    return NO;
  }

  _capability = capability;

  AVCaptureVideoDataOutput* currentOutput = [self currentOutput];
  if (!currentOutput)
    return NO;

  [self directOutputToSelf];

  _captureChanging = YES;
  dispatch_async(
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
      ^(void) { [self startCaptureInBackgroundWithOutput:currentOutput]; });
  return YES;
}

- (AVCaptureVideoDataOutput*)currentOutput {
  return [[_captureSession outputs] firstObject];
}

- (void)startCaptureInBackgroundWithOutput:
            (AVCaptureVideoDataOutput*)currentOutput {
  NSString* captureQuality =
      [NSString stringWithString:AVCaptureSessionPresetLow];
  if (_capability.width >= 1920 || _capability.height >= 1080) {
    captureQuality =
        [NSString stringWithString:AVCaptureSessionPreset1920x1080];
  } else if (_capability.width >= 1280 || _capability.height >= 720) {
    captureQuality = [NSString stringWithString:AVCaptureSessionPreset1280x720];
  } else if (_capability.width >= 640 || _capability.height >= 480) {
    captureQuality = [NSString stringWithString:AVCaptureSessionPreset640x480];
  } else if (_capability.width >= 352 || _capability.height >= 288) {
    captureQuality = [NSString stringWithString:AVCaptureSessionPreset352x288];
  }

  // begin configuration for the AVCaptureSession
  [_captureSession beginConfiguration];

  // picture resolution
  [_captureSession setSessionPreset:captureQuality];

  // take care of capture framerate now
  NSArray* sessionInputs = _captureSession.inputs;
  AVCaptureDeviceInput* deviceInput = [sessionInputs count] > 0 ?
      sessionInputs[0] : nil;
  AVCaptureDevice* inputDevice = deviceInput.device;
  if (inputDevice) {
    AVCaptureDeviceFormat* activeFormat = inputDevice.activeFormat;
    NSArray* supportedRanges = activeFormat.videoSupportedFrameRateRanges;
    AVFrameRateRange* targetRange = [supportedRanges count] > 0 ?
        supportedRanges[0] : nil;
    // Find the largest supported framerate less than capability maxFPS.
//    for (AVFrameRateRange* range in supportedRanges) {
//      //if (range.maxFrameRate <= _capability.maxFPS &&
//       //   targetRange.maxFrameRate <= range.maxFrameRate) {
//       // targetRange = range;
//    //  }
//        printf("********zhanganl range.maxFrameRate : %f *********",range.maxFrameRate);
//    }

    if (targetRange && [inputDevice lockForConfiguration:NULL]) {
        inputDevice.activeVideoMinFrameDuration = CMTimeMake(10,100);//targetRange.minFrameDuration;
      inputDevice.activeVideoMaxFrameDuration = CMTimeMake(10,150);//targetRange.minFrameDuration;
      [inputDevice unlockForConfiguration];
    }
      
      /* add by VintonLiu on 20170222 for video image rotation to natural */
      if(inputDevice.position == AVCaptureDevicePositionFront) {
          _position = AVCaptureDevicePositionFront;
      } else {
          _position = AVCaptureDevicePositionBack;
      }
      /* VintonLiu add end */
  }

  _connection = [currentOutput connectionWithMediaType:AVMediaTypeVideo];
  [self setRelativeVideoOrientation];

  // finished configuring, commit settings to AVCaptureSession.
  [_captureSession commitConfiguration];

  [_captureSession startRunning];
  [self signalCaptureChangeEnd];
}

- (void)setRelativeVideoOrientation {
  if (!_connection.supportsVideoOrientation)
    return;
    
  switch ([UIApplication sharedApplication].statusBarOrientation) {
    case UIInterfaceOrientationPortrait:
#if defined(__IPHONE_8_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_8_0
    case UIInterfaceOrientationUnknown:
#endif
      _connection.videoOrientation = AVCaptureVideoOrientationPortrait;
      break;
    case UIInterfaceOrientationPortraitUpsideDown:
      _connection.videoOrientation =
          AVCaptureVideoOrientationPortraitUpsideDown;
      break;
    case UIInterfaceOrientationLandscapeLeft:
      _connection.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
      break;
    case UIInterfaceOrientationLandscapeRight:
      _connection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
      break;
  }
}

- (int)getDeviceOrientation {
    UIDeviceOrientation orient = [UIDevice currentDevice].orientation;
    switch (orient) {
        case UIDeviceOrientationPortrait:
            // NSLog(@"Orientation Portrait 0");
            return 0;
            
        case UIDeviceOrientationLandscapeLeft:
            // NSLog(@"Orientation LandscapeLeft 270");
            return 270;
            
        case UIDeviceOrientationLandscapeRight:
            // NSLog(@"Orientation LandscapeRight 90");
            return 90;
            
        case UIDeviceOrientationPortraitUpsideDown:
            // NSLog(@"Orientation PortraitUpsideDown 180");
            return 180;
            
        default:
            // NSLog(@"Orientation Portrait 0");
            return 0;
    }
}

- (void)onVideoError:(NSNotification*)notification {
  NSLog(@"onVideoError: %@", notification);
  // TODO(sjlee): make the specific error handling with this notification.
  WEBRTC_TRACE(kTraceError,
               kTraceVideoCapture,
               _captureId,
               "%s:%s:%d [AVCaptureSession startRunning] error.",
               __FILE__,
               __FUNCTION__,
               __LINE__);
}

- (BOOL)stopCapture {
  [self waitForCaptureChangeToFinish];
  [self directOutputToNil];

  if (!_captureSession) {
    return NO;
  }

  _captureChanging = YES;
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                 ^(void) { [self stopCaptureInBackground]; });
  return YES;
}

- (void)stopCaptureInBackground {
  [_captureSession stopRunning];
  [self signalCaptureChangeEnd];
}

- (BOOL)changeCaptureInputByUniqueId:(NSString*)uniqueId {
  [self waitForCaptureChangeToFinish];
  NSArray* currentInputs = [_captureSession inputs];
  // remove current input
  if ([currentInputs count] > 0) {
    AVCaptureInput* currentInput =
        (AVCaptureInput*)[currentInputs objectAtIndex:0];

    [_captureSession removeInput:currentInput];
  }

  // Look for input device with the name requested (as our input param)
  // get list of available capture devices
  int captureDeviceCount = [DeviceInfoIosObjC captureDeviceCount];
  if (captureDeviceCount <= 0) {
    return NO;
  }

  AVCaptureDevice* captureDevice =
      [DeviceInfoIosObjC captureDeviceForUniqueId:uniqueId];

  if (!captureDevice) {
    return NO;
  }

  // now create capture session input out of AVCaptureDevice
  NSError* deviceError = nil;
  AVCaptureDeviceInput* newCaptureInput =
      [AVCaptureDeviceInput deviceInputWithDevice:captureDevice
                                            error:&deviceError];

  if (!newCaptureInput) {
    const char* errorMessage = [[deviceError localizedDescription] UTF8String];

    WEBRTC_TRACE(kTraceError,
                 kTraceVideoCapture,
                 _captureId,
                 "%s:%s:%d deviceInputWithDevice error:%s",
                 __FILE__,
                 __FUNCTION__,
                 __LINE__,
                 errorMessage);

    return NO;
  }
 
    /* add by VintonLiu on 20170222 for video image rotation to natural */
    if(captureDevice.position == AVCaptureDevicePositionFront) {
        _position = AVCaptureDevicePositionFront;
    } else {
        _position = AVCaptureDevicePositionBack;
    }
    /* VintonLiu add end */

  // try to add our new capture device to the capture session
  [_captureSession beginConfiguration];

  BOOL addedCaptureInput = NO;
  if ([_captureSession canAddInput:newCaptureInput]) {
    [_captureSession addInput:newCaptureInput];
    addedCaptureInput = YES;
  } else {
    addedCaptureInput = NO;
  }
     AVCaptureVideoDataOutput* currentOutput = [self currentOutput];
    _connection = [currentOutput connectionWithMediaType:AVMediaTypeVideo];
    [self setRelativeVideoOrientation];

  [_captureSession commitConfiguration];

  return addedCaptureInput;
}

uint8_t* temp_bgra = (uint8_t*)malloc(640*480*5);

- (void)captureOutput:(AVCaptureOutput*)captureOutput
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection*)connection {

  const int kFlags = 0;
  CVImageBufferRef videoFrame = CMSampleBufferGetImageBuffer(sampleBuffer);

  if (CVPixelBufferLockBaseAddress(videoFrame, kFlags) != kCVReturnSuccess) {
    return;
  }

  const int kYPlaneIndex = 0;
  const int kUVPlaneIndex = 1;

  uint8_t* baseAddress =
  (uint8_t*)CVPixelBufferGetBaseAddress(videoFrame);
  size_t BytesPerRow =
  CVPixelBufferGetBytesPerRow(videoFrame);
  VideoCaptureCapability tempCaptureCapability;
  tempCaptureCapability.width = CVPixelBufferGetWidth(videoFrame);
  tempCaptureCapability.height = CVPixelBufferGetHeight(videoFrame);
  tempCaptureCapability.maxFPS = _capability.maxFPS;
  tempCaptureCapability.rawType = kVideoARGB;
  tempCaptureCapability.stride = BytesPerRow/4;//yPlaneBytesPerRow;
    
  {
      int device_degrees = 0;
      int display_degrees = 0;
      int capture_degrees = 0;
      
      device_degrees = [self getDeviceOrientation];
      
//      NSLog(@"captureOutput device_degrees: %d app_orientation: %d video_orientation: %d",
//            device_degrees, app_orientation, (int)_connection.videoOrientation);
      switch (_connection.videoOrientation) {
          case AVCaptureVideoOrientationLandscapeRight:
          {
              // calc degrees for rotate video capture frame to natural orientation
              if (_position == AVCaptureDevicePositionFront) {
                  capture_degrees = (360 - (90 + device_degrees)) % 360;
              } else {
                  capture_degrees = (90 + device_degrees) % 360;
              }
              
              // local preview display rotation
              display_degrees = (360 - capture_degrees) % 360;
          }
              break;
          
          case AVCaptureVideoOrientationLandscapeLeft:
          {
              // calc degrees for rotate video capture frame to natural orientation
              if (_position == AVCaptureDevicePositionFront) {
                  if ( device_degrees % 180 ) {
                      capture_degrees = ( 90 - device_degrees + 360 ) % 360;
                  } else {
                      capture_degrees = ( 90 + device_degrees + 360) % 360;
                  }
              } else {
                  if ( device_degrees % 180 ) {
                      capture_degrees = ( 360 - (90 - device_degrees)) % 360;
                  } else {
                      capture_degrees = ( 360 - (90 + device_degrees)) % 360;
                  }
              }
              
              // local preview display rotation
              display_degrees = (360 - capture_degrees) % 360;
          }
              break;
         
          case AVCaptureVideoOrientationPortraitUpsideDown:
              // demo problem, so not test
          case AVCaptureVideoOrientationPortrait:
          default:
          {
              // calc degrees for rotate video capture frame to natural orientation
              if (_position == AVCaptureDevicePositionFront) {
                  capture_degrees = (360 - device_degrees) % 360;
              } else {
                  capture_degrees = (device_degrees + 360) % 360;
              }
              
              // local preview display rotation
              display_degrees = (360 - capture_degrees) % 360;
          }
              break;
      }
//      NSLog(@"captureOutput capture_degrees: %d display_degrees: %d",
//            capture_degrees, display_degrees);
      
      // set capture rotation
      VideoRotation current_rotation = kVideoRotation_0;
      _owner->RotationFromDegrees(capture_degrees, &current_rotation);
      _owner->SetCaptureRotation(current_rotation);
      
      // set display preview rotation
      _owner->RotationFromDegrees(display_degrees, &tempCaptureCapability.displayRotation);
  }
    
  BGRA_TO_RGB24(baseAddress,tempCaptureCapability.width*tempCaptureCapability.height*4);
  
//     dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
        //         ^(void) {
  addfilter_on_rawdata(baseAddress,tempCaptureCapability.width,tempCaptureCapability.height,temp_bgra);
  _owner->IncomingFrame(temp_bgra, tempCaptureCapability.width*tempCaptureCapability.height*4, tempCaptureCapability, 0);
   //                  });
  

  CVPixelBufferUnlockBaseAddress(videoFrame, kFlags);
}

- (void)signalCaptureChangeEnd {
  [_captureChangingCondition lock];
  _captureChanging = NO;
  [_captureChangingCondition signal];
  [_captureChangingCondition unlock];
}

- (void)waitForCaptureChangeToFinish {
  [_captureChangingCondition lock];
  while (_captureChanging) {
    [_captureChangingCondition wait];
  }
  [_captureChangingCondition unlock];
}

-(int)setFilter:(int)filter_type filter_sensity:(float)filter_sensity
{
    self.filter_type=filter_type;
    //self.filter_sensity=filter_sensity;
    set_filter(filter_type,filter_sensity);
    //printf("rtc_video_capture_ios_objc : %d,%lf",filter_type,filter_sensity);
    return 0;
}

@end
