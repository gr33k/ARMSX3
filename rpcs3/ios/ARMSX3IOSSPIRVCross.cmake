include_guard(GLOBAL)

# MoltenVK v1.4.2 pins this exact SPIRV-Cross revision in
# ExternalRevisions/SPIRV-Cross_repo_revision. The archive checksum is for the
# immutable commit codeload URL used by fetch-spirv-cross.sh.
set(ARMSX3_IOS_SPIRV_CROSS_MOLTENVK_VERSION "1.4.2")
set(ARMSX3_IOS_SPIRV_CROSS_MOLTENVK_TAG_COMMIT "db66022459ffb663aa2b50f6b018bc2e124f5edf")
set(ARMSX3_IOS_SPIRV_CROSS_REVISION "6c09849fe88c48eaed08413aa022aaa136a3a057")
set(ARMSX3_IOS_SPIRV_CROSS_ARCHIVE_SHA256 "b81b9956289950570953738e666a031ca32ff64e4fc925eba89f227c42109518")
set(ARMSX3_IOS_MOLTENVK_CONVERTER_SHA256 "124e571b7327c76ca0e340fc786deb53f114361dee3a1ae6d98c3d657a2878dc")
set(ARMSX3_IOS_SPIRV_CROSS_LICENSE_ID "Apache-2.0")
set(ARMSX3_IOS_SPIRV_CROSS_MINIMUM_IOS "15.0")
set(ARMSX3_IOS_SPIRV_CROSS_ARCHITECTURE "arm64")
set(ARMSX3_IOS_SPIRV_CROSS_NAMESPACE "MVK_spirv_cross")
set(ARMSX3_IOS_SPIRV_CROSS_TARGET "ARMSX3::SPIRVCross")
set(ARMSX3_IOS_SPIRV_CROSS_MSL_TARGET "ARMSX3::SPIRVCrossMSL")

get_filename_component(ARMSX3_IOS_SPIRV_CROSS_REPO_ROOT
    "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)

if(NOT DEFINED ARMSX3_DEPS_ROOT)
    if(DEFINED ENV{ARMSX3_DEPS_ROOT} AND NOT "$ENV{ARMSX3_DEPS_ROOT}" STREQUAL "")
        set(ARMSX3_DEPS_ROOT "$ENV{ARMSX3_DEPS_ROOT}")
    else()
        set(ARMSX3_DEPS_ROOT "${ARMSX3_IOS_SPIRV_CROSS_REPO_ROOT}/.deps")
    endif()
endif()
get_filename_component(ARMSX3_DEPS_ROOT "${ARMSX3_DEPS_ROOT}" ABSOLUTE
    BASE_DIR "${ARMSX3_IOS_SPIRV_CROSS_REPO_ROOT}")

set(ARMSX3_IOS_SPIRV_CROSS_SOURCE_DIR
    "${ARMSX3_DEPS_ROOT}/SPIRV-Cross-${ARMSX3_IOS_SPIRV_CROSS_REVISION}")
set(ARMSX3_IOS_SPIRV_CROSS_LICENSE_FILE
    "${ARMSX3_IOS_SPIRV_CROSS_SOURCE_DIR}/LICENSE")
set(ARMSX3_IOS_MOLTENVK_CONVERTER_HEADER
    "${ARMSX3_IOS_SPIRV_CROSS_SOURCE_DIR}/MoltenVKShaderConverter/SPIRVToMSLConverter.h")
set(ARMSX3_IOS_SPIRV_CROSS_FETCH_SCRIPT
    "${ARMSX3_IOS_SPIRV_CROSS_REPO_ROOT}/platforms/ios/scripts/fetch-spirv-cross.sh")
set(ARMSX3_IOS_SPIRV_CROSS_ATTRIBUTION
    "SPIRV-Cross, Khronos Group, Apache License 2.0")

function(armsx3_ios_validate_spirv_cross)
    if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
        message(FATAL_ERROR "The native Metal SPIRV-Cross lane is restricted to iOS")
    endif()
    if(NOT CMAKE_OSX_ARCHITECTURES STREQUAL ARMSX3_IOS_SPIRV_CROSS_ARCHITECTURE)
        message(FATAL_ERROR
            "SPIRV-Cross requires -DCMAKE_OSX_ARCHITECTURES=${ARMSX3_IOS_SPIRV_CROSS_ARCHITECTURE}")
    endif()
    if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
        message(FATAL_ERROR "Set -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 or newer")
    endif()
    if(CMAKE_OSX_DEPLOYMENT_TARGET VERSION_LESS ARMSX3_IOS_SPIRV_CROSS_MINIMUM_IOS)
        message(FATAL_ERROR
            "SPIRV-Cross requires iOS ${ARMSX3_IOS_SPIRV_CROSS_MINIMUM_IOS} or newer")
    endif()

    foreach(required_file IN ITEMS
        CMakeLists.txt
        LICENSE
        spirv_cross.hpp
        spirv_msl.hpp
        MoltenVKShaderConverter/SPIRVToMSLConverter.h
        .armsx3-spirv-cross-dependency)
        if(NOT EXISTS "${ARMSX3_IOS_SPIRV_CROSS_SOURCE_DIR}/${required_file}")
            message(FATAL_ERROR
                "Pinned SPIRV-Cross source is missing ${required_file}. Run: ${ARMSX3_IOS_SPIRV_CROSS_FETCH_SCRIPT}")
        endif()
    endforeach()

    file(STRINGS
        "${ARMSX3_IOS_SPIRV_CROSS_SOURCE_DIR}/.armsx3-spirv-cross-dependency"
        dependency_stamp)
    foreach(expected_line IN ITEMS
        "revision=${ARMSX3_IOS_SPIRV_CROSS_REVISION}"
        "archive_sha256=${ARMSX3_IOS_SPIRV_CROSS_ARCHIVE_SHA256}"
        "moltenvk_converter_sha256=${ARMSX3_IOS_MOLTENVK_CONVERTER_SHA256}"
        "moltenvk_version=${ARMSX3_IOS_SPIRV_CROSS_MOLTENVK_VERSION}"
        "moltenvk_tag_commit=${ARMSX3_IOS_SPIRV_CROSS_MOLTENVK_TAG_COMMIT}")
        list(FIND dependency_stamp "${expected_line}" line_index)
        if(line_index EQUAL -1)
            message(FATAL_ERROR "SPIRV-Cross dependency stamp is missing: ${expected_line}")
        endif()
    endforeach()
endfunction()

function(armsx3_ios_add_spirv_cross)
    if(TARGET ARMSX3IOSSPIRVCross)
        return()
    endif()

    armsx3_ios_validate_spirv_cross()

    if(TARGET spirv-cross-core)
        message(FATAL_ERROR
            "spirv-cross-core already exists; include the pinned iOS helper before another SPIRV-Cross provider")
    endif()

    # Match MoltenVK v1.4.2's bounded feature set. Disabling the CLI, upstream
    # tests, shared library, and unused backends keeps iOS configuration and
    # compilation within the 8 GB development host ceiling.
    set(SPIRV_CROSS_CLI OFF CACHE BOOL "" FORCE)
    set(SPIRV_CROSS_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
    set(SPIRV_CROSS_ENABLE_GLSL ON CACHE BOOL "" FORCE)
    set(SPIRV_CROSS_ENABLE_HLSL OFF CACHE BOOL "" FORCE)
    set(SPIRV_CROSS_ENABLE_MSL ON CACHE BOOL "" FORCE)
    set(SPIRV_CROSS_ENABLE_CPP OFF CACHE BOOL "" FORCE)
    set(SPIRV_CROSS_ENABLE_REFLECT ON CACHE BOOL "" FORCE)
    set(SPIRV_CROSS_ENABLE_C_API OFF CACHE BOOL "" FORCE)
    set(SPIRV_CROSS_ENABLE_UTIL OFF CACHE BOOL "" FORCE)
    set(SPIRV_CROSS_STATIC ON CACHE BOOL "" FORCE)
    set(SPIRV_CROSS_SHARED OFF CACHE BOOL "" FORCE)
    set(SPIRV_CROSS_NAMESPACE_OVERRIDE
        "${ARMSX3_IOS_SPIRV_CROSS_NAMESPACE}" CACHE STRING "" FORCE)
    set(SPIRV_CROSS_SKIP_INSTALL ON CACHE BOOL "" FORCE)

    add_subdirectory(
        "${ARMSX3_IOS_SPIRV_CROSS_SOURCE_DIR}"
        "${CMAKE_BINARY_DIR}/_deps/spirv-cross-${ARMSX3_IOS_SPIRV_CROSS_REVISION}"
        EXCLUDE_FROM_ALL)

    foreach(required_target IN ITEMS
        spirv-cross-core
        spirv-cross-glsl
        spirv-cross-msl
        spirv-cross-reflect)
        if(NOT TARGET ${required_target})
            message(FATAL_ERROR "Pinned SPIRV-Cross did not define ${required_target}")
        endif()
        set_property(TARGET ${required_target} PROPERTY SYSTEM TRUE)
    endforeach()

    add_library(ARMSX3IOSSPIRVCross INTERFACE)
    target_link_libraries(ARMSX3IOSSPIRVCross INTERFACE
        spirv-cross-core
        spirv-cross-glsl
        spirv-cross-msl
        spirv-cross-reflect)

    add_library(ARMSX3::SPIRVCross ALIAS ARMSX3IOSSPIRVCross)
    add_library(ARMSX3::SPIRVCrossCore ALIAS spirv-cross-core)
    add_library(ARMSX3::SPIRVCrossGLSL ALIAS spirv-cross-glsl)
    add_library(ARMSX3::SPIRVCrossMSL ALIAS spirv-cross-msl)
    add_library(ARMSX3::SPIRVCrossReflect ALIAS spirv-cross-reflect)
endfunction()

# SPIRV-Cross is Apache-2.0 and its fetched LICENSE must remain in source and
# distribution notices. This helper is deliberately opt-in and does not link
# it into RPCS3 automatically; GPL-2.0-only distribution compatibility must be
# resolved by the integrating project before shipping a combined binary.
