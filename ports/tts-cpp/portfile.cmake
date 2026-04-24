# tts-cpp vcpkg overlay port
#
# Builds the tts-cpp static library (target `tts-cpp::tts-cpp`).
# The library currently ships the Chatterbox Turbo pipeline; additional
# TTS engines will land under the same umbrella.
#
# ggml is consumed from the separate ggml overlay port via
# `find_package(ggml CONFIG REQUIRED)`, gated by the
# TTS_CPP_USE_SYSTEM_GGML option in the upstream CMakeLists (mirrors
# stable-diffusion-cpp's SD_USE_SYSTEM_GGML pattern).
#
# Installed artefacts:
#   include/tts-cpp/tts-cpp.h                           (generic CLI entry)
#   include/tts-cpp/chatterbox/engine.h                 (Engine API)
#   include/tts-cpp/chatterbox/s3gen_pipeline.h         (Chatterbox back-half)
#   lib/libtts-cpp.a                                    (static library)
#   share/tts-cpp/tts-cppConfig.cmake                   (CMake package config)
#   share/tts-cpp/tts-cppTargets.cmake                  (exported target)
#   share/tts-cpp/tts-cppConfigVersion.cmake            (semver companion)
#
# GPU backend selection is handled by the ggml port via vcpkg features
# (metal / vulkan / cuda / opencl), forwarded through this port's own
# features.  The relevant -DGGML_* compile-defs are forwarded into
# chatterbox.cpp's CMakeLists so its `if (GGML_METAL) ...` blocks emit
# the matching GGML_USE_* macros for the static library.
#
# The port currently pins to GustavoA1604/chatterbox.cpp on the
# `vcpkg-registry-2` branch while the fork stabilises.  Once the repo is
# transferred to the tetherto org under its final name (tts-cpp),
# bump REF + REPO + HEAD_REF in a single port-version.

vcpkg_from_github(
  OUT_SOURCE_PATH SOURCE_PATH
  REPO GustavoA1604/chatterbox.cpp
  REF f8f9145dc5e219e4a2be8c772b9c5990599d8667
  SHA512 e2378a5443cd11f64ebdc79569d70de9af6799bab8d7fca7625287304f2dd997163e1a32a49196e3c262ea060cc345bedd7d756f0f1ff5d280a903dde4b6edbf
  HEAD_REF vcpkg-registry-2
)

set(PLATFORM_OPTIONS)

if ("metal" IN_LIST FEATURES)
  list(APPEND PLATFORM_OPTIONS -DGGML_METAL=ON)
else()
  list(APPEND PLATFORM_OPTIONS -DGGML_METAL=OFF)
endif()

if ("vulkan" IN_LIST FEATURES)
  list(APPEND PLATFORM_OPTIONS -DGGML_VULKAN=ON)
else()
  list(APPEND PLATFORM_OPTIONS -DGGML_VULKAN=OFF)
endif()

vcpkg_cmake_configure(
  SOURCE_PATH "${SOURCE_PATH}"
  DISABLE_PARALLEL_CONFIGURE
  OPTIONS
    -DTTS_CPP_BUILD_LIBRARY=ON
    -DTTS_CPP_BUILD_EXECUTABLES=OFF
    -DTTS_CPP_BUILD_TESTS=OFF
    -DTTS_CPP_INSTALL=ON
    -DTTS_CPP_USE_SYSTEM_GGML=ON
    ${PLATFORM_OPTIONS}
)

vcpkg_cmake_install()

vcpkg_cmake_config_fixup(PACKAGE_NAME tts-cpp CONFIG_PATH share/tts-cpp)

vcpkg_copy_pdbs()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

if (VCPKG_LIBRARY_LINKAGE MATCHES "static")
  file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin")
  file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/bin")
endif()

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
