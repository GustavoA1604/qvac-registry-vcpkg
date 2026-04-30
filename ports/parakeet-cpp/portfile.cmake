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
    REF b7c45722264a03f4f7a5f61ae7ce714b6019bc57
    SHA512 1b75108c94509f2a8208bf970cb724e9cb871811725d0affb2fbdfca892b7122fdcabe9a5993f850c09505d745e00981ed156e45c7ba8e68930a19b6c69ec5e2
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
