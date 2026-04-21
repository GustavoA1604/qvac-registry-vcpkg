message(STATUS ">>> Building custom onnxruntime port with platform-specific patches")

# Common patches
set(ONNXRUNTIME_PATCHES
  "03-fix-dll.patch"
  "04-fix-android-binary-size.patch"
  "06-fix-array-bounds-issue-ios-sim.patch"
  "11-fix-tpause-clang.patch"
  "14-add-fp16-bias-gelu-cpu.patch"
)

# Add extra patches only for Windows builds
if("dml-ep" IN_LIST FEATURES)
  message(STATUS "Applying Windows-specific patches (DirectML)...")
  list(APPEND ONNXRUNTIME_PATCHES
    "07-fix-dml-export.patch"
    "12-fix-delayload-static-lib.patch"
  )
endif()

# Add extra patches only for Apple builds
if(VCPKG_CMAKE_SYSTEM_NAME STREQUAL "Darwin" OR VCPKG_CMAKE_SYSTEM_NAME STREQUAL "iOS")
  message(STATUS "Applying Apple-specific patches (CoreML)...")
  list(APPEND ONNXRUNTIME_PATCHES
    "07-fix-coreml-export.patch"
    "08-fix-coreml-proto-include.patch"
    "13-fix-coreml-availability.patch"
    "18-fix-coreml-external-data-path.patch"
  )
endif()

# Add extra patches only for Android builds
# Note: no additional NNAPI patch is needed for v1.24.2+ because EXPORT is already in the source
if(VCPKG_CMAKE_SYSTEM_NAME STREQUAL "Android" AND NOT "minimal-build" IN_LIST FEATURES)
  message(STATUS "Android build detected (NNAPI EP enabled via features)")
  # No additional patches needed for Android in v1.24.2+
endif()

# XNNPACK API compatibility fixes for ORT 1.24.2
if("xnnpack-ep" IN_LIST FEATURES)
  message(STATUS "Applying XNNPack patches...")
  list(APPEND ONNXRUNTIME_PATCHES
    "15-fix-xnnpack-code-cache-api.patch"
    "16-fix-xnnpack-workspace-api.patch"
    "17-fix-xnnpack-resize-api.patch"
  )
endif()

if("minimal-build" IN_LIST FEATURES)
  list(APPEND ONNXRUNTIME_PATCHES
    "09-fix-minimal-build-onnx-onnx-proto-issue.patch"
  )
endif()

vcpkg_from_github(
  OUT_SOURCE_PATH SOURCE_PATH
  REPO microsoft/onnxruntime
  REF "v${VERSION}"
  SHA512 9f634692c0edb1910616c05b08e12ac20e393f637ca14d41fa46849dfd70a3719e1952af238fe862a2d77a3f0c66d03d1201b1739c85e193e102626413d6a041
  PATCHES ${ONNXRUNTIME_PATCHES}
)

# Apple build options
set(APPLE_BUILD_OPTIONS "")
if("coreml-ep" IN_LIST FEATURES AND
   (VCPKG_CMAKE_SYSTEM_NAME STREQUAL "Darwin" OR VCPKG_CMAKE_SYSTEM_NAME STREQUAL "iOS"))
  message(STATUS "Pre-downloading coremltools for CoreML support...")

  vcpkg_download_distfile(COREMLTOOLS_ARCHIVE
    URLS "https://github.com/apple/coremltools/archive/refs/tags/7.1.zip"
    FILENAME "coremltools-7.1.zip"
    SHA512 c6645d0b48953fe4a7f3ffa34df35c40ddc764e76b9aa8ec1af282842f8346129df650514cb5bc6dde52ecb75750aac4ad159e5cfa6384146cfa72c75af77399
  )

  # Extract to the expected location for FetchContent
  set(DEPS_DIR "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-rel/_deps")
  file(MAKE_DIRECTORY "${DEPS_DIR}")

  vcpkg_extract_source_archive_ex(
    OUT_SOURCE_PATH COREMLTOOLS_SOURCE_PATH
    ARCHIVE "${COREMLTOOLS_ARCHIVE}"
    WORKING_DIRECTORY "${DEPS_DIR}"
  )

  # Copy to the expected directory name
  set(COREMLTOOLS_DIR "${DEPS_DIR}/coremltools-src")
  file(REMOVE_RECURSE "${COREMLTOOLS_DIR}")
  file(COPY "${COREMLTOOLS_SOURCE_PATH}/" DESTINATION "${COREMLTOOLS_DIR}")

  # Verify proto files exist
  file(GLOB PROTO_FILES "${COREMLTOOLS_DIR}/mlmodel/format/*.proto")
  list(LENGTH PROTO_FILES PROTO_COUNT)
  message(STATUS "Found ${PROTO_COUNT} proto files in ${COREMLTOOLS_DIR}/mlmodel/format/")

  set(APPLE_BUILD_OPTIONS
    -Dcoremltools_SOURCE_DIR=${COREMLTOOLS_DIR}
    -Dcoremltools_POPULATED=TRUE
    -DFETCHCONTENT_FULLY_DISCONNECTED=OFF
  )
endif()

# Feature mapping
vcpkg_check_features(
  OUT_FEATURE_OPTIONS FEATURE_OPTIONS
    FEATURES
      nnapi-ep onnxruntime_USE_NNAPI_BUILTIN
      coreml-ep onnxruntime_USE_COREML
      dml-ep onnxruntime_USE_DML
      xnnpack-ep onnxruntime_USE_XNNPACK
      minimal-build onnxruntime_MINIMAL_BUILD
      tests onnxruntime_BUILD_UNIT_TESTS
)

# Configure build
vcpkg_cmake_configure(
  SOURCE_PATH "${SOURCE_PATH}/cmake"
  OPTIONS
    -Donnxruntime_USE_VCPKG=ON
    -Donnxruntime_BUILD_SHARED_LIB=OFF
    -Donnxruntime_ENABLE_BITCODE=OFF
    -Donnxruntime_ENABLE_PYTHON=OFF
    -Donnxruntime_DISABLE_RTTI=OFF
    -Donnxruntime_DISABLE_EXCEPTIONS=OFF
    ${FEATURE_OPTIONS}
    ${APPLE_BUILD_OPTIONS}
)

vcpkg_cmake_install()

vcpkg_fixup_pkgconfig()

vcpkg_cmake_config_fixup(
  CONFIG_PATH lib/cmake/onnxruntime
)

# Fix: Add INTERFACE_INCLUDE_DIRECTORIES to the main onnxruntime target
set(CONFIG_FILE "${CURRENT_PACKAGES_DIR}/share/${PORT}/onnxruntimeTargets.cmake")
file(READ "${CONFIG_FILE}" _contents)
string(REPLACE
  "# Create imported target onnxruntime::onnxruntime\nadd_library(onnxruntime::onnxruntime INTERFACE IMPORTED)\n\nset_target_properties(onnxruntime::onnxruntime PROPERTIES\n  INTERFACE_LINK_LIBRARIES"
  "# Create imported target onnxruntime::onnxruntime\nadd_library(onnxruntime::onnxruntime INTERFACE IMPORTED)\n\nset_target_properties(onnxruntime::onnxruntime PROPERTIES\n  INTERFACE_INCLUDE_DIRECTORIES \"\${_IMPORT_PREFIX}/include/onnxruntime\"\n  INTERFACE_LINK_LIBRARIES"
  _contents "${_contents}")
string(REPLACE ";microkernels_prod_LIBRARY-NOTFOUND" "" _contents "${_contents}")
if(EXISTS "${CURRENT_INSTALLED_DIR}/lib/libmicrokernels-prod.a")
  string(REPLACE
    ";unofficial::pthreadpool;unofficial::pthreadpool_interface"
    ";\$<\$<NOT:\$<CONFIG:DEBUG>>:\${VCPKG_IMPORT_PREFIX}/lib/libmicrokernels-prod.a>;\$<\$<CONFIG:DEBUG>:\${VCPKG_IMPORT_PREFIX}/debug/lib/libmicrokernels-prod.a>;unofficial::pthreadpool;unofficial::pthreadpool_interface"
    _contents "${_contents}")
elseif(EXISTS "${CURRENT_INSTALLED_DIR}/lib/microkernels-prod.lib")
  string(REPLACE
    ";unofficial::pthreadpool;unofficial::pthreadpool_interface"
    ";\$<\$<NOT:\$<CONFIG:DEBUG>>:\${VCPKG_IMPORT_PREFIX}/lib/microkernels-prod.lib>;\$<\$<CONFIG:DEBUG>:\${VCPKG_IMPORT_PREFIX}/debug/lib/microkernels-prod.lib>;unofficial::pthreadpool;unofficial::pthreadpool_interface"
    _contents "${_contents}")
endif()
file(WRITE "${CONFIG_FILE}" "${_contents}")

# Fix: Change find_dependency(protobuf) to find_dependency(Protobuf) for case sensitivity
set(CONFIG_FILE "${CURRENT_PACKAGES_DIR}/share/${PORT}/onnxruntimeConfig.cmake")
file(READ "${CONFIG_FILE}" _contents)
string(REPLACE "find_dependency(protobuf)" "find_dependency(Protobuf)" _contents "${_contents}")
file(WRITE "${CONFIG_FILE}" "${_contents}")

# Cleanup
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")

# Install copyright
vcpkg_install_copyright(FILE_LIST
  "${SOURCE_PATH}/LICENSE"
  "${SOURCE_PATH}/ThirdPartyNotices.txt"
)
