cmake_minimum_required(VERSION 3.10)

project(flutter_sticker_maker_native)

# Set C standard
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Enable optimizations for Release builds
set(CMAKE_C_FLAGS_RELEASE "-O3 -DNDEBUG")
set(CMAKE_C_FLAGS_DEBUG "-O0 -g")

# Platform-specific optimizations
if(ANDROID_ABI STREQUAL "arm64-v8a" OR ANDROID_ABI STREQUAL "armeabi-v7a")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -mfpu=neon")
    add_definitions(-D__ARM_NEON)
endif()

# Include directories
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/../../../src/native)

# Source files
set(NATIVE_SOURCES
    ../../../src/native/mask_processor.c
    ../../../src/native/simd_optimizations.c
)

# Create shared library
add_library(flutter_sticker_maker_native SHARED ${NATIVE_SOURCES})

# Link libraries
target_link_libraries(flutter_sticker_maker_native
    android
    log
    m  # math library
)

# Set output directory
set_target_properties(flutter_sticker_maker_native PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}"
)