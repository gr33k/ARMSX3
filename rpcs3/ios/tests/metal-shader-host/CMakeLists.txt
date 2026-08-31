cmake_minimum_required(VERSION 3.28)

project(ARMSX3MetalShaderHostTests LANGUAGES CXX OBJCXX)

if(NOT ARMSX3_SPIRV_CROSS_SOURCE_DIR OR
   NOT EXISTS "${ARMSX3_SPIRV_CROSS_SOURCE_DIR}/spirv_msl.cpp")
    message(FATAL_ERROR "Set ARMSX3_SPIRV_CROSS_SOURCE_DIR to the verified source tree")
endif()

get_filename_component(ARMSX3_REPO_ROOT
    "${CMAKE_CURRENT_LIST_DIR}/../../../.." ABSOLUTE)
set(ARMSX3_METAL_SHADER_ROOT "${ARMSX3_REPO_ROOT}/rpcs3/Emu/RSX/MTL")

set(SPIRV_CROSS_CLI OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_GLSL ON CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_HLSL OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_MSL ON CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_CPP OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_REFLECT OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_C_API OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_UTIL OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_STATIC ON CACHE BOOL "" FORCE)
set(SPIRV_CROSS_SHARED OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_NAMESPACE_OVERRIDE "MVK_spirv_cross" CACHE STRING "" FORCE)
set(SPIRV_CROSS_SKIP_INSTALL ON CACHE BOOL "" FORCE)

add_subdirectory("${ARMSX3_SPIRV_CROSS_SOURCE_DIR}"
    "${CMAKE_BINARY_DIR}/spirv-cross" EXCLUDE_FROM_ALL)

add_executable(ARMSX3MetalShaderTranslationTests
    "${ARMSX3_METAL_SHADER_ROOT}/MTLShaderTypes.cpp"
    "${ARMSX3_METAL_SHADER_ROOT}/MTLSpirvCompiler.cpp"
    "${ARMSX3_METAL_SHADER_ROOT}/tests/MTLSpirvCompilerTests.mm")
target_include_directories(ARMSX3MetalShaderTranslationTests PRIVATE
    "${ARMSX3_METAL_SHADER_ROOT}")
target_compile_features(ARMSX3MetalShaderTranslationTests PRIVATE cxx_std_20)
target_compile_options(ARMSX3MetalShaderTranslationTests PRIVATE
    -Wall
    -Wextra
    -Werror
    "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>")
target_link_libraries(ARMSX3MetalShaderTranslationTests PRIVATE
    spirv-cross-msl
    "-framework Foundation"
    "-framework Metal")

add_executable(ARMSX3MetalShaderKeyTests
    "${ARMSX3_METAL_SHADER_ROOT}/MTLShaderTypes.cpp"
    "${ARMSX3_METAL_SHADER_ROOT}/tests/MTLShaderKeyTests.cpp")
target_include_directories(ARMSX3MetalShaderKeyTests PRIVATE
    "${ARMSX3_METAL_SHADER_ROOT}")
target_compile_features(ARMSX3MetalShaderKeyTests PRIVATE cxx_std_20)
target_compile_options(ARMSX3MetalShaderKeyTests PRIVATE
    -Wall
    -Wextra
    -Werror)
