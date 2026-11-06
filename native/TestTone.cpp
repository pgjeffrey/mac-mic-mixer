#include <obs-module.h>
#include <util/platform.h>
#include <atomic>
#include <chrono>
#include <cmath>
#include <thread>

namespace {
struct Tone {
    obs_source_t *source;
    double frequency;
    std::atomic<bool> running{true};
    std::thread thread;
    Tone(obs_source_t *s, double f) : source(s), frequency(f), thread([this] { run(); }) {}
    ~Tone() { running.store(false); if (thread.joinable()) thread.join(); }
    void run() {
        float samples[480];
        uint64_t position = 0;
        auto next = std::chrono::steady_clock::now();
        while (running.load()) {
            for (size_t i = 0; i < 480; ++i, ++position)
                samples[i] = 0.2f * std::sin(2.0 * 3.141592653589793 * frequency * position / 48000.0);
            obs_source_audio audio{};
            audio.data[0] = reinterpret_cast<const uint8_t *>(samples);
            audio.frames = 480;
            audio.speakers = SPEAKERS_MONO;
            audio.format = AUDIO_FORMAT_FLOAT;
            audio.samples_per_sec = 48000;
            audio.timestamp = os_gettime_ns();
            obs_source_output_audio(source, &audio);
            next += std::chrono::milliseconds(10);
            std::this_thread::sleep_until(next);
        }
    }
};
const char *name(void *) { return "Diagnostic tone"; }
void *create(obs_data_t *settings, obs_source_t *source) {
    return new Tone(source, obs_data_get_double(settings, "frequency"));
}
void destroy(void *value) { delete static_cast<Tone *>(value); }
}

extern "C" {
struct obs_source_info mixer_test_tone_info = {};
}

// CMake compiles this as C++; registration happens after static initialization.
struct ToneRegistration {
    ToneRegistration() {
        mixer_test_tone_info.id = "mixer_test_tone";
        mixer_test_tone_info.type = OBS_SOURCE_TYPE_INPUT;
        mixer_test_tone_info.output_flags = OBS_SOURCE_AUDIO;
        mixer_test_tone_info.get_name = name;
        mixer_test_tone_info.create = create;
        mixer_test_tone_info.destroy = destroy;
    }
} registerTone;
