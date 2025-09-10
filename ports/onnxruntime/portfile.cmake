vcpkg_from_github(
  OUT_SOURCE_PATH SOURCE_PATH
  REPO microsoft/onnxruntime
  REF "v${VERSION}"
  SHA512 028a7f48f41d2e8a453aae25ebc4cd769db389401937928b7d452fab5f8d7af8cb63eb4150daf79589845528f0e4c3bdfefa27af70d3630398990c9e8b85387b
  PATCHES
    "01-replace-deprecated-gsl-byte.patch"
    "02-add-static-lib.patch"
    "03-fix-dll.patch"
    "04-fix-android-binary-size.patch"
    "05-add-dependencies-to-config.patch"
    "06-fix-array-bounds-issue-ios-sim.patch"
)

vcpkg_check_features(
  OUT_FEATURE_OPTIONS FEATURE_OPTIONS
    FEATURES
      tests onnxruntime_BUILD_UNIT_TESTS
)

vcpkg_cmake_configure(
  SOURCE_PATH "${SOURCE_PATH}/cmake"
  OPTIONS
    -Donnxruntime_USE_VCPKG=ON
    -Donnxruntime_BUILD_SHARED_LIB=ON
    ${FEATURE_OPTIONS}
)

vcpkg_cmake_install()

vcpkg_fixup_pkgconfig()

vcpkg_cmake_config_fixup(
    CONFIG_PATH lib/cmake/onnxruntime
)

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
