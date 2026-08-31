cmake_minimum_required(VERSION 3.28)

include("${CMAKE_CURRENT_LIST_DIR}/../ARMSX3IOSSPIRVCross.cmake")

function(assert_equal actual expected label)
    if(NOT "${actual}" STREQUAL "${expected}")
        message(FATAL_ERROR "${label}: expected '${expected}', got '${actual}'")
    endif()
endfunction()

assert_equal("${ARMSX3_IOS_SPIRV_CROSS_MOLTENVK_VERSION}"
    "1.4.2" "MoltenVK version")
assert_equal("${ARMSX3_IOS_SPIRV_CROSS_MOLTENVK_TAG_COMMIT}"
    "db66022459ffb663aa2b50f6b018bc2e124f5edf" "MoltenVK tag commit")
assert_equal("${ARMSX3_IOS_SPIRV_CROSS_REVISION}"
    "6c09849fe88c48eaed08413aa022aaa136a3a057" "SPIRV-Cross revision")
assert_equal("${ARMSX3_IOS_SPIRV_CROSS_ARCHIVE_SHA256}"
    "b81b9956289950570953738e666a031ca32ff64e4fc925eba89f227c42109518"
    "SPIRV-Cross archive SHA-256")
assert_equal("${ARMSX3_IOS_SPIRV_CROSS_LICENSE_ID}" "Apache-2.0" "license")
assert_equal("${ARMSX3_IOS_SPIRV_CROSS_MINIMUM_IOS}" "15.0" "minimum iOS")
assert_equal("${ARMSX3_IOS_SPIRV_CROSS_ARCHITECTURE}" "arm64" "architecture")
assert_equal("${ARMSX3_IOS_SPIRV_CROSS_NAMESPACE}" "MVK_spirv_cross" "namespace")
assert_equal("${ARMSX3_IOS_SPIRV_CROSS_TARGET}"
    "ARMSX3::SPIRVCross" "aggregate target")
assert_equal("${ARMSX3_IOS_SPIRV_CROSS_MSL_TARGET}"
    "ARMSX3::SPIRVCrossMSL" "MSL target")

execute_process(
    COMMAND "${ARMSX3_IOS_SPIRV_CROSS_FETCH_SCRIPT}" --print-metadata
    RESULT_VARIABLE metadata_result
    OUTPUT_VARIABLE metadata
    ERROR_VARIABLE metadata_error
    OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT metadata_result EQUAL 0)
    message(FATAL_ERROR "fetch metadata failed: ${metadata_error}")
endif()

foreach(expected_line IN ITEMS
    "moltenvk_version=${ARMSX3_IOS_SPIRV_CROSS_MOLTENVK_VERSION}"
    "moltenvk_tag_commit=${ARMSX3_IOS_SPIRV_CROSS_MOLTENVK_TAG_COMMIT}"
    "revision=${ARMSX3_IOS_SPIRV_CROSS_REVISION}"
    "archive_sha256=${ARMSX3_IOS_SPIRV_CROSS_ARCHIVE_SHA256}"
    "license=${ARMSX3_IOS_SPIRV_CROSS_LICENSE_ID}")
    string(FIND "${metadata}" "${expected_line}" line_index)
    if(line_index EQUAL -1)
        message(FATAL_ERROR "fetch metadata is missing: ${expected_line}")
    endif()
endforeach()

armsx3_ios_validate_spirv_cross()

file(READ "${ARMSX3_IOS_SPIRV_CROSS_LICENSE_FILE}" license_text LIMIT 256)
string(FIND "${license_text}" "Apache License" license_index)
if(license_index EQUAL -1)
    message(FATAL_ERROR "SPIRV-Cross LICENSE is not the expected Apache-2.0 notice")
endif()

message(STATUS "SPIRV-Cross dependency metadata contracts passed")
