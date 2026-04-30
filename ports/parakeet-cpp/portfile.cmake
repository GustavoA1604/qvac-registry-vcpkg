# parakeet.cpp vcpkg overlay port
#
# Builds the qvac-parakeet.cpp ASR + diarization inference library
# (FastConformer encoder shared by CTC / TDT / EOU; Sortformer head;
# StreamEvent + EnergyVad helpers) with its own bundled ggml.
#
# Installed artefacts:
#   include/qvac-parakeet/...    (public C++ headers; Engine + StreamSession)
#   include/ggml*.h              (bundled ggml public headers)
#   lib/libqvac-parakeet.a       (static library)
#   lib/libggml*.a               (static ggml backends)
#   share/qvac-parakeet-cpp/     (CMake package config)
#   share/ggml/                  (CMake package config for the bundled ggml)
#
# Why bundle ggml instead of depending on the system `ggml` overlay port?
# qvac-parakeet.cpp is pinned to upstream ggml commit 58c38058 (Apr 9
# 2026). The system `ggml` port is the qvac-ext-ggml fork on the
# `speech` branch which carries the chatterbox metal-ops patch
# (`mul_mv Q-variant bias/residual fusion`). That fusion empirically
# breaks the EOU joint-network q8_0 matmul path (the EOU greedy decoder
# produces 0 tokens; CTC / TDT / Sortformer all keep working). Since
# qvac-parakeet.cpp's `add_subdirectory(ggml)` branch already does
# everything the system port does, we just hand it a tarball of upstream
# ggml at the right pin and let the build use it.
#
# Consumers use:
#   find_package(qvac-parakeet-cpp CONFIG REQUIRED)
#   target_link_libraries(... PRIVATE qvac-parakeet::qvac-parakeet)
#
# Pinned to a single port-version=0; if the upstream needs a fix during
# the early integration phase we overwrite this same port-version rather
# than bumping it (per the qvac-registry-vcpkg single-port-version
# policy for newly-added overlay ports).

# Release-only (no debug build) -- keep it lean. Suppress the
# "mismatching number of debug and release binaries" check.
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_BUILD_TYPE release)

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO GustavoA1604/qvac-parakeet.cpp
    REF 4fcea2b00d3d978db5320ebaa082b9d3602d1ec9
    SHA512 f5ff71d74f7eb98c3152b2d996ca4b5f66b5cfddc7887a5bed107df73cd6f21ebd86ada226fc812ce5afe75029107fc38967f79b9bddaa4dd05834f402412b57
    HEAD_REF main
)

# Drop the bundled ggml into ${SOURCE_PATH}/ggml/ so qvac-parakeet.cpp's
# CMakeLists picks it up via add_subdirectory(ggml) in the
# QVAC_PARAKEET_USE_SYSTEM_GGML=OFF (default) branch. The `parakeet`
# branch on GustavoA1604/qvac-ext-ggml is upstream ggml at the pinned
# commit (58c38058) plus two ggml-opencl patches landed as commits
# (QVAC-17997):
#   1. opencl: relax Adreno/Intel device whitelist behind
#      GGML_OPENCL_ALLOW_UNKNOWN_GPU (no-op on Adreno production builds).
#   2. opencl: persistent kernel binary cache via
#      clCreateProgramWithBinary; activates the GGML_OPENCL_CACHE_DIR
#      contract the LLM addon already plumbs.
# Carries no chatterbox metal-ops patch (lives on the qvac-ext-ggml
# `speech` branch which would break parakeet's EOU q8_0 joint-network
# matmul -- see the bundled-ggml rationale above).
vcpkg_from_github(
    OUT_SOURCE_PATH GGML_SRC
    REPO GustavoA1604/qvac-ext-ggml
    REF 8bca30a34ba06e62fe5406dc122e49d3db0eba3a
    SHA512 624ba10829dc8b19a785728903b34ded184b715b6182ba936461acb15744ce901e2b8af48356d42b7ec6b823b227f45ecb5810589794528bd4cfe056a57e9faf
    HEAD_REF parakeet
)
file(REMOVE_RECURSE "${SOURCE_PATH}/ggml")
file(RENAME "${GGML_SRC}" "${SOURCE_PATH}/ggml")

# GPU backend feature flags. The bundled ggml inherits these via
# add_subdirectory; defaults match the rest of the speech-stack ports
# (Metal default on Apple, Vulkan / OpenCL / CUDA opt-in features).
set(GGML_METAL  OFF)
set(GGML_VULKAN OFF)
set(GGML_CUDA   OFF)
set(GGML_OPENCL OFF)
if("metal" IN_LIST FEATURES)
    set(GGML_METAL ON)
endif()
if("vulkan" IN_LIST FEATURES)
    set(GGML_VULKAN ON)
endif()
if("cuda" IN_LIST FEATURES)
    set(GGML_CUDA ON)
endif()
if("opencl" IN_LIST FEATURES)
    set(GGML_OPENCL ON)
endif()

# ggml-vulkan's CMakeLists does `find_package(Vulkan COMPONENTS glslc REQUIRED)`.
# The Android NDK ships glslc at $NDK/shader-tools/<host>/glslc, but CMake's
# FindVulkan.cmake doesn't probe that path -- it only looks under $VULKAN_SDK
# and the system PATH. On a fresh macOS host with no Vulkan SDK installed but
# the Android command-line tools present, the NDK's own glslc is available
# (and is in fact the right shader compiler to pair with the NDK's vulkan
# headers / libvulkan.so), so we point CMake at it explicitly instead of
# requiring every contributor to install the LunarG SDK.
#
# Resolution order:
#   1. $ENV{ANDROID_NDK_HOME}, $ENV{ANDROID_NDK}, $ENV{ANDROID_NDK_ROOT}
#      (whichever is set; standard NDK env vars).
#   2. $ENV{ANDROID_HOME}/ndk/<latest>  (homebrew default on macOS;
#      `brew install --cask android-commandlinetools` puts the NDK here).
# The NDK ships only an x86_64 host build (which runs under Rosetta on
# Apple Silicon), so the host triple under shader-tools/ is normally
# `darwin-x86_64` / `linux-x86_64` / `windows-x86_64`. We glob the
# directory rather than hard-coding the triple.
if (VCPKG_TARGET_IS_ANDROID AND GGML_VULKAN)
    set(_pp_ndk_root "")
    foreach(_pp_var ANDROID_NDK_HOME ANDROID_NDK ANDROID_NDK_ROOT)
        if (DEFINED ENV{${_pp_var}} AND NOT "$ENV{${_pp_var}}" STREQUAL "")
            set(_pp_ndk_root "$ENV{${_pp_var}}")
            break()
        endif()
    endforeach()
    if (NOT _pp_ndk_root AND DEFINED ENV{ANDROID_HOME} AND NOT "$ENV{ANDROID_HOME}" STREQUAL "")
        # Homebrew android-commandlinetools layout: $ANDROID_HOME/ndk/<version>.
        # Pick the highest version (lexicographic sort works for X.Y.Z dot
        # version strings produced by the Android SDK manager).
        file(GLOB _pp_ndk_candidates LIST_DIRECTORIES true "$ENV{ANDROID_HOME}/ndk/*")
        if (_pp_ndk_candidates)
            list(SORT _pp_ndk_candidates)
            list(REVERSE _pp_ndk_candidates)
            list(GET _pp_ndk_candidates 0 _pp_ndk_root)
        endif()
    endif()

    if (_pp_ndk_root AND IS_DIRECTORY "${_pp_ndk_root}")
        file(GLOB _pp_glslc_candidates "${_pp_ndk_root}/shader-tools/*/glslc")
        if (_pp_glslc_candidates)
            list(GET _pp_glslc_candidates 0 _pp_glslc)
            message(STATUS "parakeet-cpp: using NDK-bundled glslc at ${_pp_glslc}")
            list(APPEND _pp_extra_cmake_options "-DVulkan_GLSLC_EXECUTABLE=${_pp_glslc}")
        else()
            message(FATAL_ERROR
                "parakeet-cpp: GGML_VULKAN=ON on Android but no glslc found under "
                "${_pp_ndk_root}/shader-tools/. Install a recent Android NDK "
                "(>= r25, ships shader-tools/<host>/glslc) or install the "
                "LunarG Vulkan SDK and set VULKAN_SDK on the host.")
        endif()

        # ggml-vulkan also #includes <vulkan/vulkan.hpp>, but the NDK only
        # ships the C headers (vulkan.h / vulkan_core.h). Detect the NDK's
        # Vulkan version and download the matching KhronosGroup/Vulkan-Headers
        # release for the C++ wrappers, then override Vulkan_INCLUDE_DIR so
        # ggml-vulkan's `target_link_libraries(... PRIVATE Vulkan::Vulkan)`
        # picks up both the C and C++ headers from the same matching tree.
        # Same approach as qvac-fabric/android-vulkan-version.cmake.
        file(GLOB _pp_ndk_host_dirs LIST_DIRECTORIES true
             "${_pp_ndk_root}/toolchains/llvm/prebuilt/*")
        set(_pp_vk_core_h "")
        foreach (_pp_ndk_host_dir IN LISTS _pp_ndk_host_dirs)
            set(_pp_candidate "${_pp_ndk_host_dir}/sysroot/usr/include/vulkan/vulkan_core.h")
            if (EXISTS "${_pp_candidate}")
                set(_pp_vk_core_h "${_pp_candidate}")
                break()
            endif()
        endforeach()
        if (NOT _pp_vk_core_h)
            message(FATAL_ERROR
                "parakeet-cpp: GGML_VULKAN=ON on Android but couldn't find "
                "vulkan_core.h under any toolchains/llvm/prebuilt/*/sysroot/ "
                "in NDK ${_pp_ndk_root}.")
        endif()
        file(READ "${_pp_vk_core_h}" _pp_vk_core_content)
        string(REGEX MATCH "VK_HEADER_VERSION ([0-9]+)" _pp_vk_patch_match "${_pp_vk_core_content}")
        if (NOT _pp_vk_patch_match)
            message(FATAL_ERROR
                "parakeet-cpp: couldn't parse VK_HEADER_VERSION from ${_pp_vk_core_h}.")
        endif()
        set(_pp_vk_patch "${CMAKE_MATCH_1}")
        string(REGEX MATCH
            "VK_HEADER_VERSION_COMPLETE VK_MAKE_API_VERSION\\(([0-9]+), ([0-9]+), ([0-9]+)"
            _pp_vk_complete_match "${_pp_vk_core_content}")
        if (NOT _pp_vk_complete_match)
            message(FATAL_ERROR
                "parakeet-cpp: couldn't parse VK_HEADER_VERSION_COMPLETE "
                "from ${_pp_vk_core_h}.")
        endif()
        set(_pp_vk_major "${CMAKE_MATCH_2}")
        set(_pp_vk_minor "${CMAKE_MATCH_3}")
        set(_pp_vk_version "${_pp_vk_major}.${_pp_vk_minor}.${_pp_vk_patch}")
        message(STATUS "parakeet-cpp: NDK reports Vulkan ${_pp_vk_version}; "
                       "downloading matching Vulkan-Headers for C++ wrappers")

        # Using file(DOWNLOAD) rather than vcpkg_from_github(SHA512 0) so the
        # tarball SHA isn't pinned per version (the NDK's Vulkan patch version
        # bumps with every NDK release; pinning would force a port-version
        # bump on every NDK upgrade). Same shape as qvac-fabric's
        # android-vulkan-version.cmake. We extract straight under
        # ${SOURCE_PATH}/.parakeet-vulkan-headers and override
        # Vulkan_INCLUDE_DIR; FindVulkan still resolves Vulkan_LIBRARY and
        # Vulkan_GLSLC_EXECUTABLE separately (the loader from NDK sysroot,
        # glslc from shader-tools/ above), so this only affects header lookup.
        set(_pp_vk_headers_root "${SOURCE_PATH}/.parakeet-vulkan-headers")
        set(_pp_vk_headers_tgz  "${_pp_vk_headers_root}/Vulkan-Headers-${_pp_vk_version}.tar.gz")
        file(MAKE_DIRECTORY "${_pp_vk_headers_root}")
        file(DOWNLOAD
            "https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v${_pp_vk_version}.tar.gz"
            "${_pp_vk_headers_tgz}"
            TLS_VERIFY ON
            STATUS _pp_vk_dl_status
        )
        list(GET _pp_vk_dl_status 0 _pp_vk_dl_code)
        if (NOT _pp_vk_dl_code EQUAL 0)
            list(GET _pp_vk_dl_status 1 _pp_vk_dl_msg)
            message(FATAL_ERROR
                "parakeet-cpp: failed to download Vulkan-Headers v${_pp_vk_version}: ${_pp_vk_dl_msg}")
        endif()
        file(ARCHIVE_EXTRACT
            INPUT "${_pp_vk_headers_tgz}"
            DESTINATION "${_pp_vk_headers_root}"
        )
        set(_pp_vk_headers_inc
            "${_pp_vk_headers_root}/Vulkan-Headers-${_pp_vk_version}/include")
        if (NOT EXISTS "${_pp_vk_headers_inc}/vulkan/vulkan.hpp")
            message(FATAL_ERROR
                "parakeet-cpp: extracted Vulkan-Headers but ${_pp_vk_headers_inc}/vulkan/vulkan.hpp "
                "is missing -- archive layout may have changed.")
        endif()
        list(APPEND _pp_extra_cmake_options
            "-DVulkan_INCLUDE_DIR=${_pp_vk_headers_inc}")
    else()
        message(FATAL_ERROR
            "parakeet-cpp: GGML_VULKAN=ON on Android but couldn't locate the "
            "Android NDK to find glslc. Set ANDROID_NDK_HOME (or ANDROID_NDK / "
            "ANDROID_NDK_ROOT) to your NDK path, or set ANDROID_HOME so that "
            "ANDROID_HOME/ndk/<version> resolves.")
    endif()
endif()

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    DISABLE_PARALLEL_CONFIGURE
    OPTIONS
        -DQVAC_PARAKEET_BUILD_LIBRARY=ON
        -DQVAC_PARAKEET_BUILD_EXECUTABLES=OFF
        -DQVAC_PARAKEET_BUILD_TESTS=OFF
        -DQVAC_PARAKEET_BUILD_EXAMPLES=OFF
        -DQVAC_PARAKEET_INSTALL=ON
        -DQVAC_PARAKEET_USE_SYSTEM_GGML=OFF
        -DBUILD_SHARED_LIBS=OFF
        # Disable parakeet.cpp's libqvac-parakeet-ggml-* output prefix in
        # the vcpkg flow. The prefix is meant to avoid shared-library
        # filename collisions when multiple addons load different ggml
        # versions in the same process; it's a no-op for shared linkage
        # and actively breaks static-link installs because the upstream
        # ggml-config.cmake exported here does
        # `find_library(GGML_LIBRARY ggml ...)` which only matches
        # `libggml*` filenames. Since this port hard-pins
        # BUILD_SHARED_LIBS=OFF (everything statically links into the
        # consuming addon's single shared object), the prefix has no
        # collision benefit here.
        -DQVAC_PARAKEET_GGML_LIB_PREFIX=OFF
        # GGML_NATIVE=ON intentionally. EOU q8_0's greedy RNN-T decode
        # is more f32-precision-sensitive than CTC / TDT (24-step argmax
        # over 1027 classes; one bad-precision step flips argmax and
        # skips a token). Building with NATIVE=OFF on Apple Silicon
        # produces visibly degraded EOU transcripts ("and so my fellow
        # ask not your country..." vs the correct "and so my fellow
        # americans ask not what your country..."); CTC and TDT keep
        # working byte-equal because their decode is more robust. ggml
        # runtime-detects CPU features on x86 / Linux so prebuilt
        # binaries stay portable across CPU revisions; on Apple Silicon
        # prebuilds are per-arch anyway.
        -DGGML_NATIVE=ON
        -DGGML_OPENMP=OFF
        -DGGML_CCACHE=OFF
        # Disable qvac-parakeet's own ccache launcher in vcpkg builds so
        # CI runs are deterministic regardless of whether ccache is on
        # the build image. ggml's own GGML_CCACHE=OFF is already set
        # above; both are needed since the parakeet ccache helper is
        # scoped to parakeet targets only and doesn't read GGML_CCACHE.
        -DQVAC_PARAKEET_CCACHE=OFF
        -DGGML_BUILD_NUMBER=1
        -DGGML_METAL=${GGML_METAL}
        -DGGML_VULKAN=${GGML_VULKAN}
        -DGGML_CUDA=${GGML_CUDA}
        -DGGML_OPENCL=${GGML_OPENCL}
        ${_pp_extra_cmake_options}
)

vcpkg_cmake_install()

# qvac-parakeet.cpp's upstream CMakeLists exports its package config to
# share/qvac-parakeet-cpp/qvac-parakeet-cppConfig.cmake; the bundled ggml
# install rules export their own to share/ggml/. No vcpkg_cmake_config_fixup
# needed for either.

# Strip duplicated include headers + debug shares from the install image.
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

# Static-only port; remove any stray bin/ that pure-static builds produce.
if (VCPKG_LIBRARY_LINKAGE MATCHES "static")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/bin")
endif()

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
