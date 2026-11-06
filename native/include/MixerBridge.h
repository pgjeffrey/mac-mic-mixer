#pragma once
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MMEngine MMEngine;

/* All engine control calls must use the same background serial queue. The main
 * thread must remain available for OBS UI tasks. JSON strings returned
 * by this interface are owned by the caller and released with mm_free_string. */
MMEngine *mm_engine_create(const char *bundle_path);
void mm_engine_destroy(MMEngine *engine);
char *mm_devices_json(void);
char *mm_engine_start(MMEngine *engine, const char *configuration_json);
void mm_engine_controls(MMEngine *engine, const char *configuration_json);
void mm_engine_stop(MMEngine *engine);
char *mm_engine_snapshot(MMEngine *engine);
/* Mac-only diagnostic: sends independent tones through two OBS input sources,
 * mixes them and reads the installed virtual microphone back. */
char *mm_engine_verify_loopback(MMEngine *engine);
void mm_free_string(char *string);

#ifdef __cplusplus
}
#endif
