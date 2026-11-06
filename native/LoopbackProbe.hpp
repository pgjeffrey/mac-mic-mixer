#pragma once
#include <AudioUnit/AudioUnit.h>
#include <atomic>
#include <string>
#include <vector>

namespace mixer {
class LoopbackProbe {
public:
    LoopbackProbe() : samples_(48000 * 6 * 2, 0.0f), scratch_(8192 * 2, 0.0f) {}
    ~LoopbackProbe() { stop(); }
    bool start(std::string &error);
    void stop();
    double amplitude(double frequency) const;
    size_t frames() const { return frames_.load(); }
    bool stereoMatches() const;
private:
    static OSStatus capture(void *, AudioUnitRenderActionFlags *, const AudioTimeStamp *, UInt32, UInt32, AudioBufferList *);
    AudioUnit unit_ = nullptr;
    std::vector<float> samples_, scratch_;
    std::atomic<size_t> frames_{0};
    std::atomic<OSStatus> error_{noErr};
};
}
