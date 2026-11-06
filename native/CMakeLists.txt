cmake_minimum_required(VERSION 3.28)
project(MacMicMixerNative LANGUAGES C CXX OBJC OBJCXX)
set(CMAKE_C_STANDARD 17)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_DEPLOYMENT_TARGET 13.0 CACHE STRING "Minimum macOS version")

if(NOT APPLE)
  message(FATAL_ERROR "Native engine requires macOS. Use make test for portable tests.")
endif()
foreach(variable OBS_SOURCE OBS_BUILD OBS_FRAMEWORK OBS_DEPS)
  if(NOT DEFINED ${variable})
    message(FATAL_ERROR "${variable} must be supplied by tools/build_macos.py")
  endif()
endforeach()

add_library(OBSCore SHARED IMPORTED)
set_target_properties(OBSCore PROPERTIES IMPORTED_LOCATION "${OBS_FRAMEWORK}/libobs")
set(obs_includes "${OBS_SOURCE}/libobs" "${OBS_BUILD}/config" "${OBS_DEPS}/include")

add_library(MixerMacInput MODULE
  input-module.c TestTone.cpp
  "${OBS_SOURCE}/plugins/mac-capture/mac-audio.c"
  "${OBS_SOURCE}/plugins/mac-capture/audio-device-enum.c"
)
target_include_directories(MixerMacInput PRIVATE ${obs_includes})
target_link_libraries(MixerMacInput PRIVATE OBSCore "-framework AudioUnit" "-framework CoreAudio" "-framework CoreFoundation")
set_target_properties(MixerMacInput PROPERTIES PREFIX "" SUFFIX ".so"
  BUILD_RPATH "${OBS_FRAMEWORK}/.." INSTALL_RPATH "@loader_path/../Frameworks")

add_library(MixerBridge STATIC MixerBridge.mm Devices.mm HALOutput.cpp LoopbackProbe.cpp)
target_include_directories(MixerBridge PRIVATE ${obs_includes} PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_compile_options(MixerBridge PRIVATE "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>")
target_link_libraries(MixerBridge PRIVATE OBSCore "-framework Foundation" "-framework CoreAudio" "-framework AudioUnit")
