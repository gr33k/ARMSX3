cmake_minimum_required(VERSION 3.28)

project(ARMSX3IOSSPIRVCrossSmoke LANGUAGES CXX OBJCXX)

include("${CMAKE_CURRENT_LIST_DIR}/../../ARMSX3IOSSPIRVCross.cmake")
armsx3_ios_add_spirv_cross()

set(ARMSX3_IOS_METAL_SHADER_ROOT
    "${CMAKE_CURRENT_LIST_DIR}/../../../Emu/RSX/MTL")

add_library(ARMSX3IOSMetalShaderCompiler STATIC
    "${ARMSX3_IOS_METAL_SHADER_ROOT}/MTLShaderTypes.cpp"
    "${ARMSX3_IOS_METAL_SHADER_ROOT}/MTLSpirvCompiler.cpp")
target_include_directories(ARMSX3IOSMetalShaderCompiler PRIVATE
    "${ARMSX3_IOS_METAL_SHADER_ROOT}")
target_compile_features(ARMSX3IOSMetalShaderCompiler PRIVATE cxx_std_20)
target_compile_options(ARMSX3IOSMetalShaderCompiler PRIVATE
    -Wall
    -Wextra
    -Werror)
target_link_libraries(ARMSX3IOSMetalShaderCompiler PRIVATE
    ARMSX3::SPIRVCrossMSL)

add_library(ARMSX3IOSMetalRuntimeScaffold STATIC
    "${ARMSX3_IOS_METAL_SHADER_ROOT}/MTLShaderTypes.cpp"
    "${ARMSX3_IOS_METAL_SHADER_ROOT}/MTLSpirvCompiler.cpp"
    "${ARMSX3_IOS_METAL_SHADER_ROOT}/MTLNativeShaderCache.mm"
    "${ARMSX3_IOS_METAL_SHADER_ROOT}/MTLRuntime.mm")
target_include_directories(ARMSX3IOSMetalRuntimeScaffold PRIVATE
    "${ARMSX3_IOS_METAL_SHADER_ROOT}")
target_compile_features(ARMSX3IOSMetalRuntimeScaffold PRIVATE cxx_std_20)
target_compile_options(ARMSX3IOSMetalRuntimeScaffold PRIVATE
    -Wall
    -Wextra
    -Werror
    "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>")
target_link_libraries(ARMSX3IOSMetalRuntimeScaffold PRIVATE
    ARMSX3::SPIRVCrossMSL
    "-framework Foundation"
    "-framework Metal"
    "-framework QuartzCore")

foreach(required_target IN ITEMS
    ARMSX3::SPIRVCross
    ARMSX3::SPIRVCrossCore
    ARMSX3::SPIRVCrossGLSL
    ARMSX3::SPIRVCrossMSL
    ARMSX3::SPIRVCrossReflect)
    if(NOT TARGET ${required_target})
        message(FATAL_ERROR "CMake helper did not expose ${required_target}")
    endif()
endforeach()

message(STATUS "SPIRV-Cross iOS Metal shader compiler smoke test configured")
