cmake_minimum_required(VERSION 3.22.1)

project(flutter_sticker_maker_native)

# Set C standard
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Enable optimizations for Release builds
set(CMAKE_C_FLAGS_RELEASE "-O3 -DNDEBUG")
set(CMAKE_C_FLAGS_DEBUG "-O0 -g")

# Platform-specific optimizations
if(ANDROID_ABI STREQUAL "arm64-v8a")
    add_definitions(-D__ARM_NEON)
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mfpu=neon")
    add_definitions(-D__ARM_NEON)
endif()

# Include directories
# Print the path
message(STATUS "Include directories: ${CMAKE_CURRENT_SOURCE_DIR}/src/cpp")
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/src/cpp)

# Source files
set(NATIVE_SOURCES
    src/cpp/mask_processor.c
    src/cpp/simd_optimizations.c
)

# Create shared library
add_library(flutter_sticker_maker_native SHARED ${NATIVE_SOURCES})

# Link libraries
target_link_libraries(flutter_sticker_maker_native
    android
    log
    m
)

# Set properties using modern CMake approach
set_target_properties(flutter_sticker_maker_native PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}"
    C_STANDARD 99
    C_STANDARD_REQUIRED ON
)

# Target-specific compile options
target_compile_options(flutter_sticker_maker_native PRIVATE
    $<$<CONFIG:Release>:-O3 -DNDEBUG>
    $<$<CONFIG:Debug>:-O0 -g>
)