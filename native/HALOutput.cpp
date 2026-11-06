#include "HALOutput.hpp"
#include "Devices.hpp"
#include "Product.hpp"
#include <cstring>

namespace mixer {
bool HALOutput::start(AudioDeviceID device, AudioPipe &pipe, std::string &error) {
    stop();
    pipe_ = &pipe;
    auto check = [&](OSStatus status, const char *step) {
        if (status == noErr) return true;
        error = std::string(step) + "（Core Audio " + std::to_string(status) + "）";
        return false;
    };
    AudioComponentDescription description{kAudioUnitType_Output, kAudioUnitSubType_HALOutput,
                                           kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponent component = AudioComponentFindNext(nullptr, &description);
    if (!component) { error = "找不到 macOS 音频输出模块"; return false; }
    if (!check(AudioComponentInstanceNew(component, &unit_), "创建虚拟输出失败")) return false;
    UInt32 on = 1, off = 0;
    AudioStreamBasicDescription format{};
    format.mSampleRate = sampleRate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    format.mBytesPerPacket = format.mBytesPerFrame = 2 * sizeof(float);
    format.mFramesPerPacket = 1;
    format.mChannelsPerFrame = 2;
    format.mBitsPerChannel = 32;
    AURenderCallbackStruct callback{render, this};
    UInt32 maximumFrames = 8192;
    if (!check(AudioUnitSetProperty(unit_, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &on, sizeof(on)), "启用输出失败") ||
        !check(AudioUnitSetProperty(unit_, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &off, sizeof(off)), "设置输出模式失败") ||
        !check(AudioUnitSetProperty(unit_, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, sizeof(device)), "选择虚拟输出失败") ||
        !check(AudioUnitSetProperty(unit_, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format)), "设置输出格式失败") ||
        !check(AudioUnitSetProperty(unit_, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximumFrames, sizeof(maximumFrames)), "设置输出缓冲失败") ||
        !check(AudioUnitSetProperty(unit_, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof(callback)), "设置输出回调失败")) {
        stop(); return false;
    }
    scratch_.assign(maximumFrames * 2, 0.0f);
    lastRender_.store(0);
    renderCount_.store(0);
    callbackError_.store(noErr);
    if (!check(AudioUnitInitialize(unit_), "初始化输出失败") ||
        !check(AudioOutputUnitStart(unit_), "启动虚拟输出失败")) {
        stop(); return false;
    }
    return true;
}

void HALOutput::stop() {
    if (unit_) {
        AudioOutputUnitStop(unit_);
        AudioUnitUninitialize(unit_);
        AudioComponentInstanceDispose(unit_);
        unit_ = nullptr;
    }
    pipe_ = nullptr;
    lastRender_.store(0);
}

OSStatus HALOutput::render(void *context, AudioUnitRenderActionFlags *flags,
                           const AudioTimeStamp *, UInt32, UInt32 frames, AudioBufferList *buffers) {
    auto &self = *static_cast<HALOutput *>(context);
    if (!buffers || !buffers->mNumberBuffers) {
        self.callbackError_.store(kAudio_ParamError);
        return kAudio_ParamError;
    }
    if (!self.pipe_ || frames * 2ULL > self.scratch_.size()) {
        for (UInt32 i = 0; i < buffers->mNumberBuffers; ++i)
            if (buffers->mBuffers[i].mData) std::memset(buffers->mBuffers[i].mData, 0, buffers->mBuffers[i].mDataByteSize);
        self.callbackError_.store(kAudio_ParamError);
        return noErr;
    }
    const auto supplied = self.pipe_->render(self.scratch_.data(), frames);
    for (UInt32 i = 0; i < buffers->mNumberBuffers; ++i) {
        auto &buffer = buffers->mBuffers[i];
        auto required = static_cast<size_t>(frames) * buffer.mNumberChannels * sizeof(float);
        if (!buffer.mData || buffer.mDataByteSize < required) {
            self.callbackError_.store(kAudio_ParamError);
            if (buffer.mData) std::memset(buffer.mData, 0, buffer.mDataByteSize);
            continue;
        }
        auto *out = static_cast<float *>(buffer.mData);
        for (UInt32 frame = 0; frame < frames; ++frame)
            for (UInt32 channel = 0; channel < buffer.mNumberChannels; ++channel)
                out[frame * buffer.mNumberChannels + channel] = self.scratch_[2 * frame];
        buffer.mDataByteSize = static_cast<UInt32>(required);
    }
    if (!supplied) *flags |= kAudioUnitRenderAction_OutputIsSilence;
    self.lastRender_.store(nowNS(), std::memory_order_relaxed);
    self.renderCount_.fetch_add(1, std::memory_order_relaxed);
    return noErr;
}
}
