# The child is discovered by a chained base recipe. The overlay composes its
# environment and enables one edit only when the condition matches.
set(test_python_env "${CONFIG_ROOT}/python-env")
file(MAKE_DIRECTORY "${test_python_env}/site-packages")
file(WRITE "${test_python_env}/pyvenv.cfg" "home = test\nversion = 3.12.3\n")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env "MISAPP_CONFIG_HOME=${CONFIG_ROOT}"
          "MISAPP_SITE_PACKAGES=${test_python_env}/site-packages"
          "TEST_APPLICATION_EXECUTABLE=${CHILD}" "TEST_FLAVOR=enabled"
          "SUBSTANCE_PAINTER_PLUGINS_PATH=old" "${LAUNCHER}" substancepainter
          -- expected-argument
  RESULT_VARIABLE recipe_status)
if(NOT recipe_status EQUAL 0)
  message(FATAL_ERROR "recipe-driven launch failed: ${recipe_status}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env "MISAPP_CONFIG_HOME=${CONFIG_ROOT}"
          "MISAPP_SITE_PACKAGES=${test_python_env}/site-packages"
          "${LAUNCHER}" validate substancepainter
  RESULT_VARIABLE validation_status)
if(NOT validation_status EQUAL 0)
  message(FATAL_ERROR "recipe validation failed: ${validation_status}")
endif()

# Other tools can consume one resolved value without parsing human-oriented output.
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env "MISAPP_CONFIG_HOME=${CONFIG_ROOT}"
          "MISAPP_SITE_PACKAGES=${test_python_env}/site-packages"
          "TEST_APPLICATION_EXECUTABLE=${CHILD}" "${LAUNCHER}" get
          substancepainter executable
  RESULT_VARIABLE get_status OUTPUT_VARIABLE resolved_executable
  OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT get_status EQUAL 0 OR NOT resolved_executable STREQUAL "${CHILD}")
  message(FATAL_ERROR "get did not expose the resolved executable: ${resolved_executable}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env "MISAPP_CONFIG_HOME=${CONFIG_ROOT}"
          "MISAPP_SITE_PACKAGES=${test_python_env}/site-packages"
          "TEST_APPLICATION_EXECUTABLE=${CHILD}" "TEST_FLAVOR=enabled"
          "${LAUNCHER}" inspect substancepainter
  RESULT_VARIABLE inspect_status OUTPUT_VARIABLE inspection)
if(NOT inspect_status EQUAL 0 OR NOT inspection MATCHES "environment.CONDITION_WORKED=yes")
  message(FATAL_ERROR "inspect did not expose the composed environment: ${inspection}")
endif()
if(NOT inspection MATCHES "environment.MISAPP_PYTHON_ENV=${test_python_env}")
  message(FATAL_ERROR "managed Python environment was not exposed: ${inspection}")
endif()

# Reject the wrong uv-managed Python ABI before starting the DCC.
set(incompatible_python_env "${CONFIG_ROOT}/python-env-incompatible")
file(MAKE_DIRECTORY "${incompatible_python_env}/site-packages")
file(WRITE "${incompatible_python_env}/pyvenv.cfg" "home = test\nversion = 3.10.9\n")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env "MISAPP_CONFIG_HOME=${CONFIG_ROOT}"
          "MISAPP_SITE_PACKAGES=${incompatible_python_env}/site-packages"
          "TEST_APPLICATION_EXECUTABLE=${CHILD}" "${LAUNCHER}" get
          substancepainter executable
  RESULT_VARIABLE incompatible_status)
if(incompatible_status EQUAL 0)
  message(FATAL_ERROR "recipe accepted an incompatible managed Python environment")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env "MISAPP_CONFIG_HOME=${CONFIG_ROOT}"
          "${LAUNCHER}" substancepainter --help
  RESULT_VARIABLE help_status OUTPUT_VARIABLE application_help)
if(NOT help_status EQUAL 0
   OR NOT application_help MATCHES "TEST_APPLICATION_EXECUTABLE"
   OR NOT application_help MATCHES "TEST_FLAVOR"
   OR NOT application_help MATCHES "CONDITION_WORKED")
  message(FATAL_ERROR "application help did not list recipe environment variables: ${application_help}")
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env "MISAPP_CONFIG_HOME=${CONFIG_ROOT}"
          "${LAUNCHER}" config-path newdcc
  RESULT_VARIABLE path_status OUTPUT_VARIABLE user_recipe_path
  OUTPUT_STRIP_TRAILING_WHITESPACE)
set(expected_recipe_path "${CONFIG_ROOT}/applications/newdcc.yml")
if(NOT path_status EQUAL 0 OR NOT user_recipe_path STREQUAL "${expected_recipe_path}")
  message(FATAL_ERROR "config-path did not return the user recipe destination: ${user_recipe_path}")
endif()
