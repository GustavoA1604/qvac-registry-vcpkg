# parakeet-cpp vcpkg overlay port
#
# Builds the parakeet-cpp ASR + diarization inference library
# (FastConformer encoder shared by CTC / TDT / EOU; Sortformer head;
# StreamEvent + EnergyVad helpers).
#
# Source layout: parakeet-cpp lives as a subfolder inside
# tetherto/qvac-ext-lib-whisper.cpp (alongside whisper.cpp itself, both
# umbrella'd under the qvac speech stack). vcpkg_from_github fetches the
# whole repo; we point cmake configure at the parakeet-cpp/ subdir below
# so the unrelated whisper / ggml / examples trees are ignored.
#
# Installed artefacts:
#   include/parakeet/...         (public C++ headers; Engine + StreamSession)
#   lib/libparakeet.a            (static library)
#   share/parakeet-cpp/          (CMake package config:
#                                 parakeet-cppConfig.cmake +
#                                 parakeet-cpp-targets[-release].cmake)
#
# ggml is consumed from the system `ggml` overlay port (speech branch).
# Both parakeet-cpp and the ggml port pin to the same upstream ggml
# commit (58c38058) and the same speech-stack patch series, so the
# linkage is identical to the previous bundled-ggml flow but the .a
# archives are deduplicated across speech-stack ports (whisper.cpp,
# parakeet-cpp, chatterbox/tts-cpp). Backend fan-out (Metal / Vulkan /
# OpenCL / CUDA) is wired through this port's vcpkg.json features which
# forward into the ggml port's matching features.
#
# Consumers use:
#   find_package(parakeet-cpp CONFIG REQUIRED)
#   target_link_libraries(... PRIVATE parakeet::parakeet)

# Release-only (no debug build) -- keep it lean. Suppress the
# "mismatching number of debug and release binaries" check.
set(VCPKG_POLICY_MISMATCHED_NUMBER_OF_BINARIES enabled)
set(VCPKG_BUILD_TYPE release)

vcpkg_from_github(
    OUT_SOURCE_PATH WHISPER_CPP_SRC
    REPO tetherto/qvac-ext-lib-whisper.cpp
    REF a6785de37dd63c43d1ea6b4c044ce7100e3c4cf7
    SHA512 5de94633bfa31c709fcb115a4d9386fd136c27ac9a4bf1f45aad565e64030720bd8525495678d68008ea4020d983d6391a70b292ffd7a4975aa4ce75f42bfb16
    HEAD_REF master
)

set(SOURCE_PATH "${WHISPER_CPP_SRC}/parakeet-cpp")
if (NOT EXISTS "${SOURCE_PATH}/CMakeLists.txt")
    message(FATAL_ERROR
        "parakeet-cpp: expected ${SOURCE_PATH}/CMakeLists.txt; the parakeet-cpp/ "
        "subfolder is missing from the fetched whisper.cpp tarball -- the upstream "
        "layout may have changed.")
endif()

# GPU backend feature flags. Forwarded into parakeet-cpp's CMakeLists so
# its `if (GGML_METAL)` / `if (GGML_VULKAN)` / etc. blocks emit the
# matching GGML_USE_* compile defines on the static library; the actual
# backend implementations come from the system ggml port.
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

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    DISABLE_PARALLEL_CONFIGURE
    OPTIONS
        -DPARAKEET_BUILD_LIBRARY=ON
        -DPARAKEET_BUILD_EXECUTABLES=OFF
        -DPARAKEET_BUILD_TESTS=OFF
        -DPARAKEET_BUILD_EXAMPLES=OFF
        -DPARAKEET_INSTALL=ON
        # Consume the system ggml port (speech branch) instead of bundling
        # a separate copy. Speech-stack ports (whisper.cpp, parakeet-cpp,
        # tts-cpp) all link the same ggml.a set this way.
        -DPARAKEET_USE_SYSTEM_GGML=ON
        -DBUILD_SHARED_LIBS=OFF
        # PARAKEET_GGML_LIB_PREFIX is a no-op when PARAKEET_USE_SYSTEM_GGML=ON
        # (parakeet-cpp's CMakeLists guards the rename behind that branch),
        # so we leave the upstream default (ON) as-is.
        # GGML_NATIVE=OFF on every triplet, matching qvac-fabric's port.
        # NATIVE=ON makes ggml-cpu probe the build host's CPU at configure
        # time (-march=native on GCC/Clang, FindSIMD.cmake -> /arch:AVX512
        # etc. on MSVC) and bake those instructions into the binary. On
        # heterogeneous CI fleets (e.g. Azure `windows-2022` / Linux
        # hosted runners where the prebuild VM has AVX-512 but the
        # integration-test VM does not) the resulting prebuild SIGILLs
        # on first ggml call. Pinning to a portable baseline keeps the
        # prebuilt artefacts loadable across the whole fleet, exactly
        # the same trade-off `qvac-fabric` / `llama-cpp` already make.
        -DGGML_NATIVE=OFF
        -DGGML_OPENMP=OFF
        # parakeet-cpp itself also `find_package(OpenMP)`s and links
        # `target_link_libraries(parakeet PRIVATE OpenMP::OpenMP_CXX)`
        # behind a top-level `option(PARAKEET_OPENMP ... ON)` (separate
        # from GGML_OPENMP). With PARAKEET_OPENMP=ON, building this port
        # for arm64-android on a macOS host that has libomp (homebrew)
        # finds OpenMP successfully, and -- because libparakeet.a is
        # STATIC -- the PRIVATE link gets propagated through the
        # exported targets file as
        #   INTERFACE_LINK_LIBRARIES "...;$<LINK_ONLY:OpenMP::OpenMP_CXX>;..."
        # The consumer's `find_package(parakeet-cpp CONFIG REQUIRED)`
        # then errors at configure time because parakeet-cppConfig.cmake
        # only `find_dependency(ggml CONFIG)`s, never OpenMP, so the
        # OpenMP::OpenMP_CXX target doesn't exist when the targets file
        # tries to set_target_properties. llama.cpp doesn't have an
        # equivalent top-level OpenMP knob (only ggml does), which is
        # why the qvac-fabric / llama-cpp ports get away with just
        # GGML_OPENMP=OFF. Match the same "no OpenMP in the prebuilt
        # speech-stack ports" stance here.
        -DPARAKEET_OPENMP=OFF
        -DGGML_CCACHE=OFF
        # Disable parakeet-cpp's own ccache launcher in vcpkg builds so
        # CI runs are deterministic regardless of whether ccache is on
        # the build image. ggml's own GGML_CCACHE=OFF is already set
        # above; both are needed since the parakeet ccache helper is
        # scoped to parakeet targets only and doesn't read GGML_CCACHE.
        -DPARAKEET_CCACHE=OFF
        -DGGML_METAL=${GGML_METAL}
        -DGGML_VULKAN=${GGML_VULKAN}
        -DGGML_CUDA=${GGML_CUDA}
        -DGGML_OPENCL=${GGML_OPENCL}
)

vcpkg_cmake_install()

vcpkg_cmake_config_fixup(PACKAGE_NAME parakeet-cpp CONFIG_PATH share/parakeet-cpp)

# Strip duplicated include headers + debug shares from the install image.
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

# Static-only port; remove any stray bin/ that pure-static builds produce.
if (VCPKG_LIBRARY_LINKAGE MATCHES "static")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin")
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/bin")
endif()

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
