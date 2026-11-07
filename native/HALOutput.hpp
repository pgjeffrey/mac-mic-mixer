#pragma once
#include "core/AudioPipe.hpp"
#include <AudioUnit/AudioUnit.h>
#include <CoreAudio/CoreAudio.h>
#include <atomic>
#include <string>
#include <vector>

namespace mixer {
class HALOutput {
public:
    ~HALOutput() { stop(); }
    bool start(AudioDeviceID device, AudioPipe &pipe, std::string &error);
    void stop();
    uint64_t lastRender() const { return lastRender_.load(); }
    uint64_t renderCount() const { return renderCount_.load(); }
    OSStatus callbackError() const { return callbackError_.load(); }
private:
    static OSStatus render(void *, AudioUnitRenderActionFlags *, const AudioTimeStamp *, UInt32, UInt32, AudioBufferList *);
    AudioUnit unit_ = nullptr;
    AudioPipe *pipe_ = nullptr;
    std::vector<float> scratch_;
    std::atomic<uint64_t> lastRender_{0}, renderCount_{0};
    std::atomic<OSStatus> callbackError_{noErr};
};
}
