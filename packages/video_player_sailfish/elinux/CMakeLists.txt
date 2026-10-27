cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "video_player_sailfish")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "video_player_sailfish_plugin")

find_package(PkgConfig)
pkg_check_modules(GLIB REQUIRED glib-2.0)
# The build adds this package to apps that use video_player, so say what
# the app's RPM needs rather than only that GStreamer is missing.
pkg_check_modules(GSTREAMER gstreamer-1.0)
if(NOT GSTREAMER_FOUND)
  message(FATAL_ERROR
    "video_player on Sailfish OS plays videos with GStreamer. In the app's "
    "rpm/<app>.yaml, add pkgconfig(gstreamer-1.0) to PkgBR, and "
    "gstreamer1.0-plugins-base, gstreamer1.0-plugins-good and "
    "gstreamer1.0-libav to Requires (see video_player_sailfish's README).")
endif()

add_library(${PLUGIN_NAME} SHARED
  "video_player_sailfish_plugin.cc"
  "gst_video_player.cc"
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

target_include_directories(${PLUGIN_NAME}
  PRIVATE
    ${GLIB_INCLUDE_DIRS}
    ${GSTREAMER_INCLUDE_DIRS}
)

target_link_libraries(${PLUGIN_NAME}
  PRIVATE
    ${GLIB_LIBRARIES}
    ${GSTREAMER_LIBRARIES}
    ${CMAKE_DL_LIBS}
)

# List of absolute paths to libraries that should be bundled with the plugin
set(video_player_sailfish_bundled_libraries
  ""
  PARENT_SCOPE
)
