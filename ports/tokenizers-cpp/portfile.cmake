vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO mlc-ai/tokenizers-cpp
    REF tags/v${VERSION}
    SHA512 e4c1a7a1f69482c4d923dbd91b1479c137dcc8f7ac8a2033f270eaf1f440d24c4f2e775a8fe4985f30cf30704de04c3102155990ce8588c76cafe4c0d33b345d
    PATCHES
        0001-build-only-hf-tokenizer.patch
        0002-fix-rust-build.patch
        0003-remove-abs-paths.patch
)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
)

vcpkg_cmake_install()

vcpkg_cmake_config_fixup(
    PACKAGE_NAME tokenizers_cpp
    CONFIG_PATH lib/cmake/tokenizers_cpp
)

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/share")

file(INSTALL "${SOURCE_PATH}/LICENSE" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME copyright)
