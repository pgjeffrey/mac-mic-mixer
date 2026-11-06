#pragma once
#define kDriver_Name "MacMicMixer"
#define kPlugIn_BundleID "com.macmicmixer.driver"
#define kPlugIn_Icon "Mixer.icns"
#define kHas_Driver_Name_Format false
#define kDevice_Name "Mac Mic Mixer"
#define kDevice2_Name "Mac Mic Mixer Output"
#define kNumber_Of_Channels 2
#define kDevice_IsHidden false
#define kDevice_HasInput true
#define kDevice_HasOutput false
#define kDevice2_IsHidden true
#define kDevice2_HasInput false
#define kDevice2_HasOutput true
/* Keep the virtual hardware clock fixed. Input rates are converted by OBS;
 * clients discover the 48 kHz format instead of changing a shared device clock. */
#define kSampleRates 48000
