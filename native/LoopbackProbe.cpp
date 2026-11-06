#include "LoopbackProbe.hpp"
#include "Devices.hpp"
#include "Product.hpp"
#include <algorithm>
#include <cmath>
#include <cstring>

namespace mixer {
bool LoopbackProbe::start(std::string &error) {
    auto check = [&](OSStatus status) {
        if (status == noErr) return true;
        error = "无法读取虚拟麦克风（Core Audio " + std::to_string(status) + "），请检查麦克风权限和驱动";
        return false;
    };
    AudioComponentDescription description{kAudioUnitType_Output, kAudioUnitSubType_HALOutput,
                                           kAudioUnitManufacturer_Apple, 0, 0};
    auto component = AudioComponentFindNext(nullptr, &description);
    if (!component) { error = "找不到系统音频输入模块"; return false; }
    if (!check(AudioComponentInstanceNew(component, &unit_))) return false;
    UInt32 on = 1, off = 0, maximumFrames = 8192;
    auto device = deviceForUID(deviceUID);
    AudioStreamBasicDescription format{};
    format.mSampleRate = sampleRate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    format.mBytesPerPacket = format.mBytesPerFrame = 2 * sizeof(float);
    format.mFramesPerPacket = 1;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 32;
    AURenderCallbackStruct callback{capture, this};
    if (!check(AudioUnitSetProperty(unit_, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, sizeof(on))) ||
        !check(AudioUnitSetProperty(unit_, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, sizeof(off))) ||
        !check(AudioUnitSetProperty(unit_, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, sizeof(device))) ||
        !check(AudioUnitSetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, sizeof(format))) ||
        !check(AudioUnitSetProperty(unit_, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximumFrames, sizeof(maximumFrames))) ||
        !check(AudioUnitSetProperty(unit_, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &callback, sizeof(callback))) ||
        !check(AudioUnitInitialize(unit_)) || !check(AudioOutputUnitStart(unit_))) {
        stop(); return false;
    }
    return true;
}

void LoopbackProbe::stop() {
    if (unit_) {
        AudioOutputUnitStop(unit_);
        AudioUnitUninitialize(unit_);
        AudioComponentInstanceDispose(unit_);
        unit_ = nullptr;
    }
}

OSStatus LoopbackProbe::capture(void *context, AudioUnitRenderActionFlags *flags,
                                const AudioTimeStamp *time, UInt32, UInt32 frames, AudioBufferList *) {
    auto &self = *static_cast<LoopbackProbe *>(context);
    if (frames * 2ULL > self.scratch_.size()) return kAudio_ParamError;
    AudioBufferList buffers{};
    buffers.mNumberBuffers = 1;
    buffers.mBuffers[0] = {2, static_cast<UInt32>(frames * 2 * sizeof(float)), self.scratch_.data()};
    OSStatus status = AudioUnitRender(self.unit_, flags, time, 1, frames, &buffers);
    if (status != noErr) { self.error_.store(status); return status; }
    auto position = self.frames_.load(std::memory_order_relaxed);
    auto count = std::min<size_t>(frames, self.samples_.size() / 2 - position);
    std::memcpy(self.samples_.data() + position * 2, self.scratch_.data(), count * 2 * sizeof(float));
    self.frames_.store(position + count, std::memory_order_release);
    return noErr;
}

double LoopbackProbe::amplitude(double frequency) const {
    auto total = frames_.load();
    const size_t skip = 48000; // Ignore graph startup and the initial silent buffers.
    if (total <= skip || error_.load() != noErr) return 0;
    double sine = 0, cosine = 0;
    for (size_t i = skip; i < total; ++i) {
        double phase = 2.0 * 3.141592653589793 * frequency * i / sampleRate;
        sine += samples_[2 * i] * std::sin(phase);
        cosine += samples_[2 * i] * std::cos(phase);
    }
    return 2.0 * std::hypot(sine, cosine) / (total - skip);
}
bool LoopbackProbe::stereoMatches() const {
    if (error_.load() != noErr) return false;
    for (size_t i = 0; i < frames_.load(); ++i)
        if (std::abs(samples_[2 * i] - samples_[2 * i + 1]) > 1e-5f) return false;
    return true;
}
}
