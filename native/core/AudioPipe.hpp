#pragma once
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace mixer {
static_assert(std::atomic<uint64_t>::is_always_lock_free, "Audio callbacks require lock-free counters");
static_assert(std::atomic<float>::is_always_lock_free, "Audio callbacks require lock-free gain");

/* One producer (libobs' mixed-audio callback), one consumer (the HAL output
 * callback). Neither callback allocates or waits on a lock. Only the consumer
 * moves read_; overflow drops new frames, and the consumer bounds queued delay.
 * reset() is only legal after BOTH callbacks have been stopped. */
class AudioPipe {
public:
    explicit AudioPipe(size_t capacity = 16384, size_t maximumBacklog = 4096,
                       size_t recoveryBacklog = 2048)
        : samples_(std::max<size_t>(capacity, 2)),
          maximumBacklog_(std::min(maximumBacklog, samples_.size())),
          recoveryBacklog_(std::min(recoveryBacklog, maximumBacklog_)) {}

    void setGain(float gain) noexcept {
        gain_.store(std::isfinite(gain) ? std::clamp(gain, 0.0f, 2.0f) : 0.0f);
    }

    size_t push(const float *stereo, size_t frames) noexcept {
        if (!stereo) return 0;
        const auto write = write_.load(std::memory_order_relaxed);
        const auto read = read_.load(std::memory_order_acquire);
        const auto available = samples_.size() - static_cast<size_t>(write - read);
        const auto count = std::min(frames, available);
        const float gain = gain_.load(std::memory_order_relaxed);
        float peak = 0.0f;
        uint64_t clipped = 0;
        for (size_t i = 0; i < count; ++i) {
            float left = std::isfinite(stereo[2 * i]) ? stereo[2 * i] : 0.0f;
            float right = std::isfinite(stereo[2 * i + 1]) ? stereo[2 * i + 1] : 0.0f;
            float mono = (0.5f * left + 0.5f * right) * gain;
            peak = std::max(peak, std::abs(mono));
            if (std::abs(mono) > 1.0f) ++clipped;
            samples_[(write + i) % samples_.size()] = std::clamp(mono, -1.0f, 1.0f);
        }
        peak_.store(peak, std::memory_order_relaxed);
        clipped_.fetch_add(clipped, std::memory_order_relaxed);
        dropped_.fetch_add(frames - count, std::memory_order_relaxed);
        write_.store(write + count, std::memory_order_release);
        return count;
    }

    /* Stereo interleaved. Both channels always contain the same mixed signal. */
    size_t render(float *stereo, size_t frames) noexcept {
        if (!stereo) return 0;
        auto read = read_.load(std::memory_order_relaxed);
        const auto write = write_.load(std::memory_order_acquire);
        auto available = static_cast<size_t>(write - read);
        if (available > maximumBacklog_) {
            const auto skip = available - recoveryBacklog_;
            read += skip;
            available -= skip;
            dropped_.fetch_add(skip, std::memory_order_relaxed);
        }
        const auto count = std::min(frames, available);
        for (size_t i = 0; i < count; ++i) {
            float sample = samples_[(read + i) % samples_.size()];
            stereo[2 * i] = sample;
            stereo[2 * i + 1] = sample;
        }
        std::fill(stereo + 2 * count, stereo + 2 * frames, 0.0f);
        read_.store(read + count, std::memory_order_release);
        if (count < frames) underrun_.fetch_add(frames - count, std::memory_order_relaxed);
        return count;
    }

    void reset() noexcept {
        read_.store(0);
        write_.store(0);
        dropped_.store(0);
        underrun_.store(0);
        clipped_.store(0);
        peak_.store(0.0f);
        std::fill(samples_.begin(), samples_.end(), 0.0f);
    }

    uint64_t dropped() const noexcept { return dropped_.load(); }
    uint64_t underrun() const noexcept { return underrun_.load(); }
    uint64_t clipped() const noexcept { return clipped_.load(); }
    float peak() const noexcept { return peak_.load(); }

private:
    std::vector<float> samples_;
    const size_t maximumBacklog_;
    const size_t recoveryBacklog_;
    alignas(64) std::atomic<uint64_t> write_{0};
    alignas(64) std::atomic<uint64_t> read_{0};
    std::atomic<float> gain_{0.75f};
    std::atomic<float> peak_{0.0f};
    std::atomic<uint64_t> dropped_{0}, underrun_{0}, clipped_{0};
};

} // namespace mixer
