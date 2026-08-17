cmake_minimum_required(VERSION 3.24)
project(misapp VERSION 0.1.0 LANGUAGES NONE)

find_program(ZIG_EXECUTABLE zig REQUIRED)
if(WIN32)
  set(NATIVE_SUFFIX ".exe")
endif()
set(MISAPP_BINARY "${CMAKE_CURRENT_BINARY_DIR}/misapp${NATIVE_SUFFIX}")
set(TEST_CHILD_BINARY "${CMAKE_CURRENT_BINARY_DIR}/native-child${NATIVE_SUFFIX}")

add_custom_command(
  OUTPUT "${MISAPP_BINARY}"
  COMMAND "${ZIG_EXECUTABLE}" build-exe "${CMAKE_CURRENT_SOURCE_DIR}/native/launcher.zig"
          -O ReleaseSmall -femit-bin=${MISAPP_BINARY}
  DEPENDS native/launcher.zig
  VERBATIM)
add_custom_target(misapp ALL DEPENDS "${MISAPP_BINARY}")
install(PROGRAMS "${MISAPP_BINARY}" DESTINATION "${SKBUILD_SCRIPTS_DIR}")

include(CTest)
if(BUILD_TESTING)
  add_custom_command(
    OUTPUT "${TEST_CHILD_BINARY}"
    COMMAND "${ZIG_EXECUTABLE}" build-exe "${CMAKE_CURRENT_SOURCE_DIR}/native/test_child.zig"
            -O ReleaseSmall -femit-bin=${TEST_CHILD_BINARY}
    DEPENDS native/test_child.zig
    VERBATIM)
  add_custom_target(native-child ALL DEPENDS "${TEST_CHILD_BINARY}")
  add_test(NAME launcher-help COMMAND "${MISAPP_BINARY}" --help)
  add_test(NAME launcher-zig-unit-tests
           COMMAND "${ZIG_EXECUTABLE}" test "${CMAKE_CURRENT_SOURCE_DIR}/native/launcher.zig")
  add_test(
    NAME launcher-yaml-recipe
    COMMAND "${CMAKE_COMMAND}" -DLAUNCHER=${MISAPP_BINARY}
            -DCHILD=${TEST_CHILD_BINARY}
            -DCONFIG_ROOT=${CMAKE_CURRENT_SOURCE_DIR}/tests/config
            -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/recipe.cmake)
  add_test(
    NAME launcher-rejects-invalid-yaml
    COMMAND "${CMAKE_COMMAND}" -E env
            "MISAPP_CONFIG_HOME=${CMAKE_CURRENT_SOURCE_DIR}/tests/config"
            "${MISAPP_BINARY}" validate invalid)
  set_tests_properties(launcher-rejects-invalid-yaml PROPERTIES WILL_FAIL TRUE)
endif()
