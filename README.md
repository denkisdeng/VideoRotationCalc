# VideoRotationCalc
- **Android 采集图像转正处理**

**App Rotation**: 应用UI横竖屏方向, 返回角度为逆时针方向

**Camera orientation**: 摄像头角度

**Device orientation**: 设备旋转角度, 与横竖屏无关，顺时针0, 90, 180, 270

\  | App Rotation | Camera orientation | home bottom |
---|---|---| --- |
**portrait**         | 0   | Front: 270  Back: 90 | on the bottom |
**landscape**        | 90  | Front: 270  Back: 90 | on the right |
**reversePortrait**  | 180 | Front: 270  Back: 90 | on the upside |
**reverseLandscape** | 270 | Front: 270  Back: 90 | on the left |


```
orient 为Camera安装角度，即Camera的info.orientation, rotation 为加速器旋转角度，即设备旋转角度

前置摄像头：
portrait，reversePortrait，landscape，reverseLandscape 应用，
        0°旋转，采集图像是 90° 旋转，需顺时针270°才为正；
        90°旋转，采集图像是 180° 旋转，需顺时针180°为自然方向；
        180°旋转，采集图像是 270° 旋转，需顺时针90°图像为自然方向正；
        270°旋转，采集图像是 0° 旋转，图像为自然方向正。
        
        图像转正角度计算公式: (orient - rotation) % 360
        (270 - 0 ) % 360 = 270
        (270 - 90 ) % 360 = 180
        (270 - 180 ) % 360 = 90
        (270 - 270) % 360 = 0
注：系统对前置相机采集到的图像默认做了镜像处理。

后置摄像头：
portrait，reversePortrait，landscape，reverseLandscape 应用
    0°旋转，采集图像是 270° 旋转，需顺时针90°才为正；
    90°旋转，采集图像是 180° 旋转，需顺时针180°为自然方向；
    180°旋转，采集图像是 90° 旋转，需顺时针270°图像为自然方向正；
    270°旋转，采集图像是 0° 旋转，图像为自然方向正。
    
    图像转正角度计算公式: (orient + rotation) % 360 
    (90 + 0) % 360 = 90
    (90 + 90) % 360 = 180
    (90 + 180) % 360 = 270
    (90 + 270) % 360 = 0

经验证，摄像头采集图像转正与横竖屏没有必然联系。
```

```
图像转正角度计算：

private void startOrientationChangeListener() {
  	mOrientationEventListener = new OrientationEventListener(context) {
  		
  		@Override
  		public void onOrientationChanged(int orientation) {
  			// TODO Auto-generated method stub
  			if ( orientation == OrientationEventListener.ORIENTATION_UNKNOWN) {
//  				mOrientation = -1;
  			} else if ( orientation <= 45 || orientation > 315 ) {
  				mOrientation = 0;
  			} else if ( orientation > 45 && orientation <= 135 ) {
  				mOrientation = 90;
  			} else if ( orientation > 135 && orientation <= 225 ) {
  				mOrientation = 180;
  			} else if ( orientation > 225 && orientation <= 315 ) {
  				mOrientation = 270;
  			}
  		}
  	};
}

public void onPreviewFrame(byte[] data, Camera callbackCamera) {
    int rotation = mOrientation;    
    if (info.facing == Camera.CameraInfo.CAMERA_FACING_BACK) {
        rotation = (info.orientation + rotation) % 360;
    } else if ( info.facing == Camera.CameraInfo.CAMERA_FACING_FRONT) {
    	rotation = (info.orientation - rotation) % 360;
    }
}
```

```
本地预览图像旋转角度：

private int getDeviceOrientation() {
    int orientation = 0;
    if (context != null) {
      WindowManager wm = (WindowManager) context.getSystemService(
          Context.WINDOW_SERVICE);
      switch(wm.getDefaultDisplay().getRotation()) {
        case Surface.ROTATION_90:
          // landscape, home button on the right
          orientation = 90;
          break;
          
        case Surface.ROTATION_180:
          // reversePortrait, home button on the top
          orientation = 180;
          break;
          
        case Surface.ROTATION_270:
          // reverseLandscape, , home button on the left
          orientation = 270;
          break;
          
        case Surface.ROTATION_0:
          //portrait, home button on the bottom
        default:
          orientation = 0;
          break;
      }
    }
    return orientation;
}

int resultRotation = 0;
int degrees = getDeviceOrientation();
// rotation is 90(facing back) or 270(facing front)
if (info.facing == Camera.CameraInfo.CAMERA_FACING_FRONT) {
  // This is a front facing camera.  SetDisplayOrientation will flip
  // the image horizontally before doing the rotation.
  resultRotation = (rotation + degrees) % 360; 
  resultRotation = ( 360 - resultRotation ) % 360; // Compensate for the mirror.
} else {
  // Back-facing camera.
  resultRotation = (rotation - degrees + 360) % 360;
}

// set preview orientation
camera.setDisplayOrientation( resultRotation % 360);
```


- **IOS 采集图像转正处理**

```
经验证，IOS 可以调用 setVideoOrientation() 设置输出视频的方向，
即可以进行自动转正，但存在切换过程中出现输出图像条纹过渡的问题。
因此，在实时通话时暂不考虑此方法。

-(void) viewWillLayoutSubviews
{
    // Handle camera
    if (_videoPreviewLayer)
    {
        _videoPreviewLayer.frame = self.view.bounds;

        for (AVCaptureOutput* outcap in _captureSession.outputs)
        {
            for(AVCaptureConnection* con in outcap.connections)
            {
                switch ([[UIDevice currentDevice] orientation])
                {

                    case UIInterfaceOrientationPortrait:
                        [con setVideoOrientation:AVCaptureVideoOrientationPortrait];

                        break;
                    case UIInterfaceOrientationLandscapeRight:
                        [con setVideoOrientation:AVCaptureVideoOrientationLandscapeLeft]; //home button on right. Refer to .h not doc
                        break;
                    case UIInterfaceOrientationLandscapeLeft:
                        [con setVideoOrientation:AVCaptureVideoOrientationLandscapeRight]; //home button on left. Refer to .h not doc
                        break;
                    case UIInterfaceOrientationPortraitUpsideDown:
                        [con setVideoOrientation:AVCaptureVideoOrientationPortraitUpsideDown]; //home button on left. Refer to .h not doc
                        break;
                    default:
                        [con setVideoOrientation:AVCaptureVideoOrientationPortrait]; //for portrait upside down. Refer to .h not doc
                        break;
                }
            }
        }
    }
}

```

IOS 采集图像转正处理：
```
1. 启动摄像头或切换摄像头时，根据应用横竖屏设置系统图像输出角度。
对于不是使用系统图像预览层AVCaptureVideoPreviewLayer 
进行本地预览的应用，对此设置后，本地图像预览时就是正常的。

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

2. 计算转正采集图像的角度
因 WebRTC 本地预览图像与编码图像是同一个视频帧，所以转正了编码前图像后，本地预览图像需要转回原来角度。

- (void)captureOutput:(AVCaptureOutput*)captureOutput
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection*)connection {
    
    int device_degrees = 0;
    int display_degrees = 0;
    int capture_degrees = 0;
      
    device_degrees = [self getDeviceOrientation];
    
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
```
