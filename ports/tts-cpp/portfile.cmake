# tts-cpp vcpkg overlay port
#
# Builds the QVAC TTS static library (target `qvac-tts::qvac-tts`).
# The library currently ships the Chatterbox Turbo pipeline; additional
# TTS engines will land under the same umbrella.
#
# ggml is consumed from the separate ggml overlay port via
# `find_package(ggml CONFIG REQUIRED)`, gated by the
# QVAC_TTS_USE_SYSTEM_GGML option in the upstream CMakeLists (mirrors
# stable-diffusion-cpp's SD_USE_SYSTEM_GGML pattern).
#
# Installed artefacts:
#   include/qvac-tts/qvac-tts.h                        (generic CLI entry)
#   include/qvac-tts/chatterbox/s3gen_pipeline.h       (Chatterbox back-half)
#   lib/libqvac-tts.a                                  (static library)
#   share/qvac-tts-cpp/qvac-tts-cppConfig.cmake        (CMake package config)
#
# GPU backend selection is handled by the ggml port via vcpkg features
# (metal / vulkan / cuda / opencl), forwarded through this port's own
# features.  The relevant -DGGML_* compile-defs are forwarded into
# chatterbox.cpp's CMakeLists so its `if (GGML_METAL) ...` blocks emit
# the matching GGML_USE_* macros for the static library.
#
# The port currently pins to GustavoA1604/chatterbox.cpp on the
# `vcpkg-registry` branch while the fork stabilises.  Once the repo is
# transferred to the tetherto org under its final name (qvac-tts.cpp),
# bump REF + REPO + HEAD_REF in a single port-version.

vcpkg_from_github(
  OUT_SOURCE_PATH SOURCE_PATH
  REPO GustavoA1604/chatterbox.cpp
  REF 01d8fe101624f3ed70b62f372c78560a681be522
  SHA512 6b14fe627c58420760cf73891ef0da07cad16c24a39e431e6ab31866dec060c4647e64a2a14c9180993dd6360284304d7fb917f479db9edb1662e40059598e7e
  HEAD_REF vcpkg-registry
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
    -DQVAC_TTS_BUILD_LIBRARY=ON
    -DQVAC_TTS_BUILD_EXECUTABLES=OFF
    -DQVAC_TTS_BUILD_TESTS=OFF
    -DQVAC_TTS_INSTALL=ON
    -DQVAC_TTS_USE_SYSTEM_GGML=ON
    ${PLATFORM_OPTIONS}
)

vcpkg_cmake_install()

vcpkg_copy_pdbs()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

if (VCPKG_LIBRARY_LINKAGE MATCHES "static")
  file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin")
  file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/bin")
endif()

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
