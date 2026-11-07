#include "MixerBridge.h"
#include "../native/Devices.hpp"
#include <obs.h>
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <iostream>

namespace {
std::atomic<int> startupCalls{0};
std::atomic<bool> finished{false};
}

// Device fixtures let the real engine reach its OBS initialization boundary.
namespace mixer {
AudioDeviceID deviceForUID(const std::string &) { return 42; }
bool deviceAlive(AudioDeviceID device) { return device != kAudioObjectUnknown; }
std::optional<bool> deviceRunningSomewhere(AudioDeviceID) { return false; }
uint32_t channelCount(AudioDeviceID, AudioObjectPropertyScope) { return 2; }
uint64_t nowNS() noexcept { return 1; }
std::vector<Device> inputDevices() { return {}; }
}

extern "C" bool obs_startup(const char *locale, const char *path, profiler_name_store_t *store) {
    if (![NSThread isMainThread]) {
        std::cerr << "OBS startup reached macOS platform initialization on a background thread\n";
        std::exit(EXIT_FAILURE);
    }
    ++startupCalls;
    using Startup = bool (*)(const char *, const char *, profiler_name_store_t *);
    auto startup = reinterpret_cast<Startup>(dlsym(RTLD_NEXT, "obs_startup"));
    if (!startup) std::exit(EXIT_FAILURE);
    return startup(locale, path, store);
}

int main() {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
                       dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            std::cerr << "Engine startup did not complete within 30 seconds\n";
            std::exit(EXIT_FAILURE);
        });
        auto queue = dispatch_queue_create("com.macmicmixer.test.engine", DISPATCH_QUEUE_SERIAL);
        dispatch_async(queue, ^{
            // Missing graphics resources stop each attempt before capture starts.
            auto *engine = mm_engine_create("/MacMicMixer-test-missing-bundle");
            for (int attempt = 0; attempt < 20; ++attempt) {
                char *result = mm_engine_start(engine, "{\"inputs\":[{\"deviceUID\":\"fixture\"}]}");
                if (!result || !std::strstr(result, "\"ok\":false")) {
                    std::cerr << "Failed startup did not return an error\n";
                    std::exit(EXIT_FAILURE);
                }
                mm_free_string(result);
                mm_engine_stop(engine);
            }
            mm_engine_destroy(engine);
            finished.store(true);
        });
        while (!finished.load())
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
        if (startupCalls.load() != 20) return EXIT_FAILURE;
        std::cout << "20 background engine start/stop attempts initialized OBS on the main thread\n";
    }
}
