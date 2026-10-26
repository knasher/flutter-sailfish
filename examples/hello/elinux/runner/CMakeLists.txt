cmake_minimum_required(VERSION 3.15)
project(runner LANGUAGES CXX)

if(FLUTTER_TARGET_BACKEND_TYPE MATCHES "gbm")
  add_definitions(-DFLUTTER_TARGET_BACKEND_GBM)
elseif(FLUTTER_TARGET_BACKEND_TYPE MATCHES "eglstream")
  add_definitions(-DFLUTTER_TARGET_BACKEND_EGLSTREAM)
elseif(FLUTTER_TARGET_BACKEND_TYPE MATCHES "x11")
  add_definitions(-DFLUTTER_TARGET_BACKEND_X11)
else()
  add_definitions(-DFLUTTER_TARGET_BACKEND_WAYLAND)
endif()

add_executable(${BINARY_NAME}
  "flutter_window.cc"
  "main.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)
apply_standard_settings(${BINARY_NAME})
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
add_dependencies(${BINARY_NAME} flutter_assemble)

# Sailfish OS: the app RPM installs this binary as /usr/bin/${BINARY_NAME} and
# the bundle in /usr/share/${BINARY_NAME}, as Sailjail expects. The binary
# finds its libraries by RPATH: Sailjail's firejail is setuid, so glibc drops
# LD_LIBRARY_PATH. flutter-sfos-aot sets FLUTTER_SFOS_LIBDIR (the runtime's
# libflutter_elinux_wayland.so).
target_compile_definitions(${BINARY_NAME} PRIVATE
  FLUTTER_SFOS_BINARY_NAME="${BINARY_NAME}")
set(SFOS_RPATH "$ORIGIN/lib" "/usr/share/${BINARY_NAME}/lib")
if(DEFINED ENV{FLUTTER_SFOS_LIBDIR})
  list(APPEND SFOS_RPATH "$ENV{FLUTTER_SFOS_LIBDIR}")
else()
  message(WARNING "FLUTTER_SFOS_LIBDIR is not set (an older flutter-sfos-aot?), "
    "so /usr/bin/${BINARY_NAME} won't find the flutter-sfos runtime.")
endif()
set_target_properties(${BINARY_NAME} PROPERTIES INSTALL_RPATH "${SFOS_RPATH}")
