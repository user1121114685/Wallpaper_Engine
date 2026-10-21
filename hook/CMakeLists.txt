cmake_minimum_required(VERSION 3.21)
project(steamcmd_hook LANGUAGES CXX)

if(NOT WIN32 OR NOT MSVC OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "This project packages only 64-bit SteamCMD hooks and workers.")
endif()

set(DETOURS_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/vendor/Detours/src"
    CACHE PATH "Pinned Microsoft Detours source directory")

add_library(detours STATIC
  "${DETOURS_SOURCE_DIR}/detours.cpp"
  "${DETOURS_SOURCE_DIR}/modules.cpp"
  "${DETOURS_SOURCE_DIR}/disasm.cpp"
  "${DETOURS_SOURCE_DIR}/image.cpp"
  "${DETOURS_SOURCE_DIR}/creatwth.cpp"
  "${DETOURS_SOURCE_DIR}/disolx86.cpp"
  "${DETOURS_SOURCE_DIR}/disolx64.cpp"
  "${DETOURS_SOURCE_DIR}/disolia64.cpp"
  "${DETOURS_SOURCE_DIR}/disolarm.cpp"
  "${DETOURS_SOURCE_DIR}/disolarm64.cpp"
)
target_include_directories(detours PUBLIC "${DETOURS_SOURCE_DIR}")
target_compile_definitions(detours PRIVATE WIN32_LEAN_AND_MEAN _WIN32_WINNT=0x0602)

add_library(steamcmd_hook SHARED steamcmd_hook.cpp steamcmd_hook.def)
target_include_directories(steamcmd_hook PRIVATE "${DETOURS_SOURCE_DIR}")
target_compile_definitions(steamcmd_hook PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX _WIN32_WINNT=0x0602)
target_compile_features(steamcmd_hook PRIVATE cxx_std_17)
target_compile_options(steamcmd_hook PRIVATE /W4 /utf-8 /EHsc)
target_link_libraries(steamcmd_hook PRIVATE detours Shell32)
set_target_properties(steamcmd_hook PROPERTIES
  PREFIX ""
  OUTPUT_NAME "steamcmd_hook"
)

add_executable(steamcmd_worker steamcmd_launcher.cpp)
target_compile_features(steamcmd_worker PRIVATE cxx_std_17)
target_compile_options(steamcmd_worker PRIVATE /W4 /utf-8 /EHsc)
set_target_properties(steamcmd_worker PROPERTIES
  OUTPUT_NAME "steamcmd_worker"
)

add_executable(steamcmd_fixture tests/hook_fixture.cpp)
target_compile_features(steamcmd_fixture PRIVATE cxx_std_17)
target_compile_options(steamcmd_fixture PRIVATE /W4 /utf-8 /EHsc)

install(TARGETS steamcmd_worker steamcmd_hook
  RUNTIME DESTINATION . LIBRARY DESTINATION .)
