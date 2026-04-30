cmake_minimum_required(VERSION 3.14)

set(EPHEMERAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ephemeral")
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
set(FLUTTER_MANAGED_DIR "${FLUTTER_MANAGED_DIR}" PARENT_SCOPE)

include("${EPHEMERAL_DIR}/generated_config.cmake")

set(FLUTTER_LIBRARY "${EPHEMERAL_DIR}/flutter_windows.dll")
set(FLUTTER_LIBRARY "${FLUTTER_LIBRARY}" PARENT_SCOPE)
set(FLUTTER_LIBRARY_HEADERS
  "${EPHEMERAL_DIR}/flutter_export.h"
  "${EPHEMERAL_DIR}/flutter_messenger.h"
  "${EPHEMERAL_DIR}/flutter_plugin_registrar.h"
  "${EPHEMERAL_DIR}/flutter_texture_registrar.h"
)
set(FLUTTER_ICU_DATA_FILE "${EPHEMERAL_DIR}/icudtl.dat" PARENT_SCOPE)
set(PROJECT_BUILD_DIR "${PROJECT_DIR}/build/" PARENT_SCOPE)
set(AOT_LIBRARY "${PROJECT_DIR}/build/windows/app.so")

list(APPEND FLUTTER_LIBRARY_HEADERS
  "${EPHEMERAL_DIR}/cpp_client_wrapper/core_implementations.cc"
  "${EPHEMERAL_DIR}/cpp_client_wrapper/standard_codec.cc"
)
set(FLUTTER_WRAPPER_SOURCES
  "${EPHEMERAL_DIR}/cpp_client_wrapper/core_implementations.cc"
  "${EPHEMERAL_DIR}/cpp_client_wrapper/standard_codec.cc"
  "${EPHEMERAL_DIR}/cpp_client_wrapper/plugin_registrar.cc"
  "${EPHEMERAL_DIR}/cpp_client_wrapper/flutter_engine.cc"
  "${EPHEMERAL_DIR}/cpp_client_wrapper/flutter_view_controller.cc"
)
set_source_files_properties(${FLUTTER_LIBRARY_HEADERS} ${FLUTTER_WRAPPER_SOURCES} PROPERTIES GENERATED TRUE)

add_library(flutter INTERFACE)
target_include_directories(flutter INTERFACE "${EPHEMERAL_DIR}")
target_link_libraries(flutter INTERFACE "${EPHEMERAL_DIR}/flutter_windows.dll.lib")
add_dependencies(flutter flutter_assemble)

add_library(flutter_wrapper_app STATIC
  ${FLUTTER_WRAPPER_SOURCES}
)
target_link_libraries(flutter_wrapper_app PUBLIC flutter)
target_include_directories(flutter_wrapper_app PUBLIC "${EPHEMERAL_DIR}")
add_dependencies(flutter_wrapper_app flutter_assemble)

add_custom_command(
  OUTPUT ${FLUTTER_LIBRARY_HEADERS}
         "${EPHEMERAL_DIR}/flutter_windows.dll"
         "${EPHEMERAL_DIR}/flutter_windows.dll.lib"
         "${EPHEMERAL_DIR}/flutter_export.h"
         "${EPHEMERAL_DIR}/icudtl.dat"
         "${CMAKE_CURRENT_BINARY_DIR}/_phony_"
  COMMAND ${CMAKE_COMMAND} -E env
    ${FLUTTER_TOOL_ENVIRONMENT}
    "${FLUTTER_ROOT}/packages/flutter_tools/bin/tool_backend.bat"
      windows-x64 $<CONFIG>
  VERBATIM
)

add_custom_target(flutter_assemble DEPENDS
  "${EPHEMERAL_DIR}/flutter_windows.dll"
  ${FLUTTER_LIBRARY_HEADERS}
)
