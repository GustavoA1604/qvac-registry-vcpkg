# tts-cpp vcpkg overlay port
#
# Builds the QVAC TTS static library (target `qvac-tts::qvac-tts`) on top
# of a vendored, patched ggml snapshot.  Currently the library ships the
# Chatterbox Turbo pipeline; additional TTS engines will land under the
# same umbrella.
#
# Installed artefacts:
#   include/qvac-tts/qvac-tts.h                        (generic CLI entry)
#   include/qvac-tts/chatterbox/s3gen_pipeline.h       (Chatterbox back-half)
#   lib/libqvac-tts.a                                  (static library)
#   lib/libggml*.a                                     (vendored ggml)
#   share/qvac-tts-cpp/qvac-tts-cppConfig.cmake        (CMake package config)
#   share/ggml/ggml-config.cmake                       (CMake package config)
#
# GPU backend selection is handled at runtime via ggml's backend registry.
# vcpkg features toggle which backends are compiled in:
#   metal  -> GGML_METAL=ON   (macOS/iOS, default-feature on Apple)
#   vulkan -> GGML_VULKAN=ON  (default-feature on windows/linux/android)
#
# The port currently pins to GustavoA1604/chatterbox.cpp on the
# `vcpkg-registry` branch while the fork stabilises.  Once the repo is
# transferred to the tetherto org under its final name (qvac-tts.cpp),
# bump REF + REPO + HEAD_REF in a single port-version.

vcpkg_from_github(
  OUT_SOURCE_PATH SOURCE_PATH
  REPO GustavoA1604/chatterbox.cpp
  REF 7f21622e00c3079aa54900289c5beae89e441527
  SHA512 c483183451a07a1be3777d0f1d26c4322d422c9f3a99568834c650ff71214e88049548e722b686b073c0fea4a6cf07ea9411042fa1e735f2f29f929615f405c8
  HEAD_REF vcpkg-registry
)

# Android: NDK ships C Vulkan headers but no vulkan.hpp.  Rather than
# depending on the vcpkg vulkan-headers port (which may diverge from NDK),
# detect the NDK's exact Vulkan version and pull the matching C++ headers
# from KhronosGroup/Vulkan-Headers into ggml/src/ so the backend build
# finds them on the default include path (mirrors whisper-cpp's setup).
if (VCPKG_TARGET_IS_ANDROID)
  include(${CMAKE_CURRENT_LIST_DIR}/android-vulkan-version.cmake)
  detect_ndk_vulkan_version()
  message(STATUS "Using Vulkan C++ wrappers from version: ${vulkan_version}")
  file(DOWNLOAD
    "https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v${vulkan_version}.tar.gz"
    "${SOURCE_PATH}/vulkan-sdk-${vulkan_version}.tar.gz"
    TLS_VERIFY ON
  )

  file(ARCHIVE_EXTRACT
    INPUT "${SOURCE_PATH}/vulkan-sdk-${vulkan_version}.tar.gz"
    DESTINATION "${SOURCE_PATH}"
  )

  file(COPY "${SOURCE_PATH}/Vulkan-Headers-${vulkan_version}/include/"
       DESTINATION "${SOURCE_PATH}/ggml/src/")

  file(REMOVE_RECURSE "${SOURCE_PATH}/Vulkan-Headers-${vulkan_version}")
endif()

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

# Android-specific ggml tuning.  `ggml-vulkan` requires
# `find_package(Vulkan COMPONENTS glslc REQUIRED)`, but the microsoft/vcpkg
# `vulkan` port only ships the loader + headers (no `glslc`).  The NDK
# bundles one under `shader-tools/<host>/glslc`, so point CMake at it
# explicitly.  Without this the configure fails with:
#   Could NOT find Vulkan (missing: glslc) (found version "...")
#
# The Vulkan backend is linked statically into libggml.a (same as
# whisper-cpp's Android setup).  `libvulkan.so` is a NEEDED dependency,
# but Android always ships it system-side so that's fine.  DL-mode
# backends are blocked by the vendored ggml@58c38058 check
# `GGML_BACKEND_DL requires BUILD_SHARED_LIBS`; the tetherto fork of
# ggml used by the standalone `ggml` port patches that check out, but
# we don't reach for that fork from this port today.
if (VCPKG_TARGET_IS_ANDROID)
  string(TOLOWER "${CMAKE_HOST_SYSTEM_NAME}" _host_system_name_lower)
  file(GLOB _shader_tools_host_dirs LIST_DIRECTORIES true
       "$ENV{ANDROID_NDK_HOME}/shader-tools/${_host_system_name_lower}-*")
  if(_shader_tools_host_dirs)
    list(GET _shader_tools_host_dirs 0 _shader_tools_host_dir)
    set(_ndk_glslc "${_shader_tools_host_dir}/glslc")
    if(EXISTS "${_ndk_glslc}")
      message(STATUS "Using NDK glslc: ${_ndk_glslc}")
      list(APPEND PLATFORM_OPTIONS "-DVulkan_GLSLC_EXECUTABLE=${_ndk_glslc}")
    else()
      message(FATAL_ERROR
        "NDK glslc not found at ${_ndk_glslc}; ensure ANDROID_NDK_HOME points at a "
        "recent NDK (r23+) that ships shader-tools/")
    endif()
  else()
    message(FATAL_ERROR
      "Could not locate $ENV{ANDROID_NDK_HOME}/shader-tools/${_host_system_name_lower}-* "
      "(is ANDROID_NDK_HOME set to a valid NDK install?)")
  endif()

  list(APPEND PLATFORM_OPTIONS
    -DGGML_VULKAN_DISABLE_COOPMAT=ON
    -DGGML_VULKAN_DISABLE_COOPMAT2=ON
  )
endif()

vcpkg_cmake_configure(
  SOURCE_PATH "${SOURCE_PATH}"
  DISABLE_PARALLEL_CONFIGURE
  OPTIONS
    -DQVAC_TTS_BUILD_LIBRARY=ON
    -DQVAC_TTS_BUILD_EXECUTABLES=OFF
    -DQVAC_TTS_BUILD_TESTS=OFF
    -DQVAC_TTS_INSTALL=ON
    -DGGML_CCACHE=OFF
    -DGGML_OPENMP=OFF
    -DGGML_NATIVE=OFF
    -DGGML_BUILD_TESTS=OFF
    -DGGML_BUILD_EXAMPLES=OFF
    -DBUILD_SHARED_LIBS=OFF
    ${PLATFORM_OPTIONS}
)

vcpkg_cmake_install()

# qvac-tts-cpp's Config.cmake is hand-written and already installed at
# share/qvac-tts-cpp/ by our CMakeLists (no cmake-generated paths inside
# it), so only ggml's auto-generated package config needs fixup.  Upstream
# ggml installs at lib/cmake/ggml/ (not share/ggml/), so pass CONFIG_PATH
# explicitly to match — otherwise fixup tries to relocate from share/ and
# trips on the missing debug/share/ggml tree.
vcpkg_cmake_config_fixup(PACKAGE_NAME ggml CONFIG_PATH lib/cmake/ggml)

vcpkg_copy_pdbs()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

if (VCPKG_LIBRARY_LINKAGE MATCHES "static")
  file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin")
  file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/bin")
endif()

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
