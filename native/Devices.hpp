#pragma once
#include <CoreAudio/CoreAudio.h>
#include <cstdint>
#include <string>
#include <vector>

namespace mixer {
struct Device {
    std::string uid, name;
    uint32_t channels = 0;
    double sampleRate = 0;
};
AudioDeviceID deviceForUID(const std::string &uid);
bool deviceAlive(AudioDeviceID device);
uint32_t channelCount(AudioDeviceID device, AudioObjectPropertyScope scope);
std::vector<Device> inputDevices();
uint64_t nowNS() noexcept;
}
