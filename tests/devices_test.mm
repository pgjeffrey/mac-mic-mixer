#include "../native/Devices.hpp"
#include "../native/Product.hpp"
#import <Foundation/Foundation.h>
#include <cstdlib>
#include <iostream>

static void checkLookup(const std::string &uid, AudioDeviceID expected) {
    auto actual = mixer::deviceForUID(uid);
    if (actual != expected) {
        std::cerr << "UID lookup failed for " << uid << ": expected " << expected
                  << ", got " << actual << '\n';
        std::exit(EXIT_FAILURE);
    }
}

int main() {
    @autoreleasepool {
        AudioObjectPropertyAddress address{kAudioHardwarePropertyDevices,
                                          kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        UInt32 size = 0;
        if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, nullptr, &size) != noErr)
            return EXIT_FAILURE;
        std::vector<AudioDeviceID> devices(size / sizeof(AudioDeviceID));
        if (size && AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, nullptr, &size, devices.data()) != noErr)
            return EXIT_FAILURE;
        for (auto device : devices) {
            CFStringRef uid = nullptr;
            size = sizeof(uid);
            address.mSelector = kAudioDevicePropertyDeviceUID;
            if (AudioObjectGetPropertyData(device, &address, 0, nullptr, &size, &uid) != noErr || !uid)
                return EXIT_FAILURE;
            NSString *text = (__bridge_transfer NSString *)uid;
            checkLookup(text.UTF8String, device);
        }
        checkLookup("", kAudioObjectUnknown);
        checkLookup("com.macmicmixer.test.nonexistent-device", kAudioObjectUnknown);
        if (mixer::deviceRunningSomewhere(kAudioObjectUnknown).has_value()) return EXIT_FAILURE;
        auto microphone = mixer::deviceForUID(mixer::deviceUID);
        auto output = mixer::deviceForUID(mixer::outputUID);
        if (microphone && (!mixer::deviceAlive(microphone) || !mixer::deviceAlive(output) ||
                           !mixer::channelCount(output, kAudioDevicePropertyScopeOutput) ||
                           !mixer::deviceRunningSomewhere(microphone).has_value() ||
                           !mixer::deviceRunningSomewhere(output).has_value()))
            return EXIT_FAILURE;
        std::cout << "Core Audio UID lookup passed for " << devices.size()
                  << " devices, empty and missing UIDs; mixer endpoints "
                  << microphone << " / " << output << '\n';
    }
}
