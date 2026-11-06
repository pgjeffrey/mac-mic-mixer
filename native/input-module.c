#include <obs-module.h>

/* The upstream mac-audio.c and audio-device-enum.c are compiled unchanged.
 * This module registers only the microphone source; no screen/video capture. */
OBS_DECLARE_MODULE()
OBS_MODULE_USE_DEFAULT_LOCALE("mac-capture", "en-US")
MODULE_EXPORT const char *obs_module_description(void) { return "Mac Mic Mixer audio inputs"; }
extern struct obs_source_info coreaudio_input_capture_info;
extern struct obs_source_info mixer_test_tone_info;
bool obs_module_load(void) {
    obs_register_source(&coreaudio_input_capture_info);
    obs_register_source(&mixer_test_tone_info);
    return true;
}
