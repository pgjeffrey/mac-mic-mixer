#include "AudioPipe.hpp"
#include <cassert>
#include <cstdio>
#include <limits>
#include <thread>

using mixer::AudioPipe;

int main() {
    AudioPipe pipe(16, 16, 8);
    pipe.setGain(1.0f);
    float input[] = {0.2f, 0.6f, -0.8f, 0.0f};
    float output[8] = {};
    assert(pipe.push(input, 2) == 2);
    assert(pipe.render(output, 4) == 2);
    assert(std::abs(output[0] - 0.4f) < 1e-6f);
    assert(output[0] == output[1] && output[2] == output[3]);
    assert(output[4] == 0.0f && output[7] == 0.0f);
    assert(pipe.underrun() == 2);

    pipe.reset();
    pipe.setGain(2.0f);
    const float bad[] = {1.0f, 1.0f, -2.0f, -2.0f,
                         std::numeric_limits<float>::quiet_NaN(), 0.0f};
    pipe.push(bad, 3);
    pipe.render(output, 3);
    assert(output[0] == 1.0f && output[2] == -1.0f && output[4] == 0.0f);
    assert(pipe.clipped() == 2);
    pipe.setGain(0.0f);
    pipe.push(input, 2);
    pipe.render(output, 2);
    assert(output[0] == 0.0f && output[3] == 0.0f);

    // Full queues cannot grow. Recovery discards stale audio on the consumer.
    AudioPipe bounded(8, 6, 4);
    bounded.setGain(1.0f);
    float ones[24];
    std::fill(ones, ones + 24, 0.5f);
    assert(bounded.push(ones, 12) == 8);
    assert(bounded.dropped() == 4);
    assert(bounded.render(output, 4) == 4);
    assert(bounded.dropped() == 8);
    assert(output[0] == 0.5f && output[7] == 0.5f);
    bounded.reset();
    bounded.render(output, 4);
    assert(output[0] == 0.0f && output[7] == 0.0f);

    // Wrap-around and concurrent producer/consumer exercise the actual SPSC
    // interface used by the OBS and HAL callbacks. Samples are monotonic IDs.
    AudioPipe concurrent(1024, 1024, 512);
    concurrent.setGain(1.0f);
    constexpr size_t total = 100000;
    std::thread producer([&] {
        for (size_t i = 1; i <= total;) {
            float sample = static_cast<float>(i) / static_cast<float>(total + 1);
            float pair[] = {sample, sample};
            if (concurrent.push(pair, 1) == 1) ++i;
            else std::this_thread::yield();
        }
    });
    float previous = 0.0f;
    for (size_t received = 0; received < total;) {
        float pair[2];
        if (concurrent.render(pair, 1) == 1) {
            assert(pair[0] > previous && pair[0] == pair[1]);
            previous = pair[0];
            ++received;
        } else std::this_thread::yield();
    }
    producer.join();
    std::puts("AudioPipe: mono mix, clipping, mute, bounded buffering, stale-audio recovery and SPSC concurrency passed");
}
