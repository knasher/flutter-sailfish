// Copyright 2021 Sony Group Corporation. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "gst_video_player.h"

#include <dlfcn.h>

#include <cstring>
#include <iostream>

namespace {
// How long Init waits for the first frame. It runs on the platform thread,
// so a decoder that never produces one must not freeze the app.
constexpr GstClockTime kPrerollTimeout = 5 * GST_SECOND;

// Frames from Sailfish OS's hardware video decoder (gst-droid's droidvdec):
// Android graphics buffers, which only the GPU can read.
constexpr char kDroidQueueBuffer[] = "memory:DroidMediaQueueBuffer";

// gst-droid makes EGLImages of its frames through the Nemo GStreamer
// interfaces library, which it loads; EGL is loaded by the embedder. Both are
// looked up at run time, so apps need no extra headers to build.
using CreateEGLImage = void* (*)(GstMemory* mem, void* egl_display,
                                 void* egl_context);
using DestroyEGLImageKHR = unsigned int (*)(void* egl_display,
                                            void* egl_image);

CreateEGLImage CreateEGLImageFunction() {
  static CreateEGLImage function = [] {
    void* library = dlopen("libgstnemointerfaces-1.0.so.0", RTLD_NOW);
    return library ? reinterpret_cast<CreateEGLImage>(dlsym(
                         library, "nemo_gst_egl_image_memory_create_image"))
                   : nullptr;
  }();
  return function;
}

DestroyEGLImageKHR DestroyEGLImageFunction() {
  static DestroyEGLImageKHR function = [] {
    using GetProcAddress = void* (*)(const char* name);
    void* library = dlopen("libEGL.so.1", RTLD_NOW);
    auto get_proc_address =
        library ? reinterpret_cast<GetProcAddress>(
                      dlsym(library, "eglGetProcAddress"))
                : nullptr;
    return get_proc_address ? reinterpret_cast<DestroyEGLImageKHR>(
                                  get_proc_address("eglDestroyImageKHR"))
                            : nullptr;
  }();
  return function;
}

// Whether the hardware decoder can be used: it is installed and not ranked
// out (an app can still turn it off with
// GST_PLUGIN_FEATURE_RANK=droidvdec:NONE), and its frames can be shown.
bool HardwareDecoding() {
  GstPluginFeature* feature =
      gst_registry_lookup_feature(gst_registry_get(), "droidvdec");
  if (!feature) {
    return false;
  }
  const bool ranked = gst_plugin_feature_get_rank(feature) > GST_RANK_NONE;
  gst_object_unref(feature);
  return ranked && CreateEGLImageFunction() && DestroyEGLImageFunction();
}

// Whether droidvdec has had data since its last STREAM_START.
struct StreamStartGuard {
  bool started = false;
  bool data = false;
};

// playbin's decodebin sends droidvdec a second, identical STREAM_START after
// its caps. GStreamer's decoders drain on each one, and gst-droid then waits,
// with no time limit, for its codec to end a stream it was never given. The
// codec on Jolla Phone 2026 never does, so the first frame never came. With
// no data in between, the repeat has nothing to drain, so it is dropped.
GstPadProbeReturn GuardStreamStart(GstPad* pad, GstPadProbeInfo* info,
                                   gpointer user_data) {
  auto* guard = static_cast<StreamStartGuard*>(user_data);
  if (!(info->type & GST_PAD_PROBE_TYPE_EVENT_DOWNSTREAM)) {
    guard->data = true;
    return GST_PAD_PROBE_OK;
  }
  if (GST_EVENT_TYPE(GST_PAD_PROBE_INFO_EVENT(info)) !=
      GST_EVENT_STREAM_START) {
    return GST_PAD_PROBE_OK;
  }
  if (guard->started && !guard->data) {
    return GST_PAD_PROBE_DROP;
  }
  guard->started = true;
  guard->data = false;
  return GST_PAD_PROBE_OK;
}

void OnElementAdded(GstBin* bin, GstBin* sub_bin, GstElement* element,
                    gpointer user_data) {
  GstElementFactory* factory = gst_element_get_factory(element);
  if (!factory || strcmp(GST_OBJECT_NAME(factory), "droidvdec") != 0) {
    return;
  }
  GstPad* pad = gst_element_get_static_pad(element, "sink");
  if (!pad) {
    return;
  }
  gst_pad_add_probe(
      pad,
      static_cast<GstPadProbeType>(GST_PAD_PROBE_TYPE_EVENT_DOWNSTREAM |
                                   GST_PAD_PROBE_TYPE_BUFFER |
                                   GST_PAD_PROBE_TYPE_BUFFER_LIST),
      GuardStreamStart, new StreamStartGuard(),
      [](gpointer guard) { delete static_cast<StreamStartGuard*>(guard); });
  gst_object_unref(pad);
}

// The app's cache folder: ~/.cache/<OrganizationName>/<ApplicationName> from
// the [X-Sailjail] section of its desktop file, or ~/.cache/<binary name>,
// found as path_provider_sailfish finds it.
std::string AppCacheDir() {
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  g_autofree gchar* binary = g_path_get_basename(exe ? exe : "");
  g_autofree gchar* desktop = g_strconcat(binary, ".desktop", nullptr);
  for (const char* dir :
       {"/usr/share/applications", "/etc/sailjail/applications"}) {
    g_autofree gchar* path = g_build_filename(dir, desktop, nullptr);
    g_autoptr(GKeyFile) file = g_key_file_new();
    if (!g_key_file_load_from_file(file, path, G_KEY_FILE_NONE, nullptr)) {
      continue;
    }
    g_autofree gchar* organization = g_key_file_get_string(
        file, "X-Sailjail", "OrganizationName", nullptr);
    g_autofree gchar* application = g_key_file_get_string(
        file, "X-Sailjail", "ApplicationName", nullptr);
    if (organization && *organization && application && *application) {
      g_autofree gchar* cache = g_build_filename(
          g_get_home_dir(), ".cache", organization, application, nullptr);
      return cache;
    }
  }
  g_autofree gchar* cache =
      g_build_filename(g_get_home_dir(), ".cache", binary, nullptr);
  return cache;
}

// Sailjail only shows GStreamer's plugin cache (~/.cache/gstreamer-1.0) to
// apps with the Audio permission. Without it, GStreamer would load every
// plugin each time it starts (about half a second), so the cache goes in the
// app's own cache folder instead, unless the app chose one in GST_REGISTRY.
// GStreamer only takes that path from the environment.
void UseAppRegistry() {
  if (g_getenv("GST_REGISTRY") || g_getenv("GST_REGISTRY_1_0")) {
    return;
  }
  g_autofree gchar* shared =
      g_build_filename(g_get_user_cache_dir(), "gstreamer-1.0", nullptr);
  if (g_file_test(shared, G_FILE_TEST_IS_DIR)) {
    return;
  }
  const std::string dir = AppCacheDir() + "/gstreamer-1.0";
  if (g_mkdir_with_parents(dir.c_str(), 0700) != 0) {
    return;
  }
  g_setenv("GST_REGISTRY", (dir + "/registry.bin").c_str(), FALSE);
}
}  // namespace

GstVideoPlayer::GstVideoPlayer(
    const std::string& uri, std::unique_ptr<VideoPlayerStreamHandler> handler)
    : stream_handler_(std::move(handler)) {
  gst_.pipeline = nullptr;
  gst_.playbin = nullptr;
  gst_.video_convert = nullptr;
  gst_.video_sink = nullptr;
  gst_.output = nullptr;
  gst_.bus = nullptr;
  gst_.buffer = nullptr;

  uri_ = ParseUri(uri);
  if (!CreatePipeline()) {
    std::cerr << "Failed to create a pipeline" << std::endl;
    DestroyPipeline();
    return;
  }
}

GstVideoPlayer::~GstVideoPlayer() {
  Stop();
  DestroyPipeline();
}

// static
// Called before the first video rather than at start-up, as GStreamer loads
// every plugin when it has no plugin cache yet.
void GstVideoPlayer::GstLibraryLoad() {
  if (gst_is_initialized()) {
    return;
  }
  UseAppRegistry();
  gst_init(NULL, NULL);
}

// static
void GstVideoPlayer::GstLibraryUnload() {
  if (gst_is_initialized()) {
    gst_deinit();
  }
}

bool GstVideoPlayer::Init() {
  if (!gst_.pipeline) {
    return false;
  }

  // Prerolls before getting information from the pipeline.
  if (!Preroll()) {
    DestroyPipeline();
    return false;
  }

  // Sets internal video size and buffier.
  GetVideoSize(width_, height_);
  if (!uses_egl_images_) {
    pixels_.reset(new uint32_t[width_ * height_]);
  }

  stream_handler_->OnNotifyInitialized();

  return true;
}

bool GstVideoPlayer::Play() {
  if (gst_element_set_state(gst_.pipeline, GST_STATE_PLAYING) ==
      GST_STATE_CHANGE_FAILURE) {
    std::cerr << "Failed to change the state to PLAYING" << std::endl;
    return false;
  }

  stream_handler_->OnNotifyPlaying(true);
  return true;
}

bool GstVideoPlayer::Pause() {
  if (gst_element_set_state(gst_.pipeline, GST_STATE_PAUSED) ==
      GST_STATE_CHANGE_FAILURE) {
    std::cerr << "Failed to change the state to PAUSED" << std::endl;
    return false;
  }

  stream_handler_->OnNotifyPlaying(false);
  return true;
}

bool GstVideoPlayer::Stop() {
  if (gst_element_set_state(gst_.pipeline, GST_STATE_READY) ==
      GST_STATE_CHANGE_FAILURE) {
    std::cerr << "Failed to change the state to READY" << std::endl;
    return false;
  }

  stream_handler_->OnNotifyPlaying(false);
  return true;
}

bool GstVideoPlayer::SetVolume(double volume) {
  if (!gst_.playbin) {
    return false;
  }

  volume_ = volume;
  g_object_set(gst_.playbin, "volume", volume, NULL);
  return true;
}

bool GstVideoPlayer::SetPlaybackRate(double rate) {
  if (!gst_.playbin) {
    return false;
  }

  if (rate <= 0) {
    std::cerr << "Rate " << rate << " is not supported" << std::endl;
    return false;
  }

  auto position = GetCurrentPosition();
  if (position < 0) {
    return false;
  }

  if (!gst_element_seek(gst_.pipeline, rate, GST_FORMAT_TIME,
                        GST_SEEK_FLAG_FLUSH, GST_SEEK_TYPE_SET,
                        position * GST_MSECOND, GST_SEEK_TYPE_SET,
                        GST_CLOCK_TIME_NONE)) {
    std::cerr << "Failed to set playback rate to " << rate
              << " (gst_element_seek failed)" << std::endl;
    return false;
  }

  playback_rate_ = rate;
  mute_ = (rate < 0.5 || rate > 2);
  g_object_set(gst_.playbin, "mute", mute_, NULL);

  return true;
}

bool GstVideoPlayer::SetSeek(int64_t position) {
  auto nanosecond = position * 1000 * 1000;
  if (!gst_element_seek(
          gst_.pipeline, playback_rate_, GST_FORMAT_TIME,
          (GstSeekFlags)(GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_KEY_UNIT),
          GST_SEEK_TYPE_SET, nanosecond, GST_SEEK_TYPE_SET,
          GST_CLOCK_TIME_NONE)) {
    std::cerr << "Failed to seek " << nanosecond << std::endl;
    return false;
  }
  last_position_ = position;
  return true;
}

int64_t GstVideoPlayer::GetDuration() {
  GstFormat fmt = GST_FORMAT_TIME;
  gint64 duration_msec;
  if (!gst_element_query_duration(gst_.pipeline, fmt, &duration_msec)) {
    std::cerr << "Failed to get duration" << std::endl;
    return -1;
  }
  duration_msec /= GST_MSECOND;
  return duration_msec;
}

int64_t GstVideoPlayer::GetCurrentPosition() {
  gint64 position = 0;

  // GStreamer has no position while a seek flushes the pipeline (the
  // hardware decoder restarts its codec then), and sometimes when playing
  // streaming videos. Sony's version failed the app's call; this reports the
  // last position, or where the seek goes, as Android does.
  if (gst_element_query_position(gst_.pipeline, GST_FORMAT_TIME, &position)) {
    last_position_ = position / GST_MSECOND;
  }

  // TODO: We need to handle this code in the proper plase.
  // The VideoPlayer plugin doesn't have a main loop, so EOS message
  // received from GStreamer cannot be processed directly in a callback
  // function. This is because the event channel message of playback complettion
  // needs to be thrown in the main thread.
  {
    std::unique_lock<std::mutex> lock(mutex_event_completed_);
    if (is_completed_) {
      is_completed_ = false;
      lock.unlock();

      if (auto_repeat_) {
        SetSeek(0);
      } else {
        stream_handler_->OnNotifyCompleted();
      }
    }
  }

  return last_position_;
}

// Sony's version could show dmabuf frames through GStreamer's GL library;
// Sailfish OS's hardware decoder gives Android graphics buffers instead.
void* GstVideoPlayer::GetEGLImage(void* egl_display) {
  std::lock_guard<std::shared_mutex> lock(mutex_buffer_);
  if (!gst_.buffer || gst_buffer_n_memory(gst_.buffer) == 0) {
    return nullptr;
  }
  // EGL_NO_CONTEXT, as EGL_ANDROID_image_native_buffer requires.
  void* image = CreateEGLImageFunction()(gst_buffer_peek_memory(gst_.buffer, 0),
                                         egl_display, nullptr);
  if (!image) {
    return nullptr;
  }
  // Keep this frame from the decoder until the texture shows the next one;
  // the previous one goes back.
  gst_buffer_replace(&shown_buffer_, gst_.buffer);
  return image;
}

// static
void GstVideoPlayer::DestroyEGLImage(void* egl_display, void* egl_image) {
  DestroyEGLImageFunction()(egl_display, egl_image);
}

const uint8_t* GstVideoPlayer::GetFrameBuffer() {
  std::shared_lock<std::shared_mutex> lock(mutex_buffer_);
  if (!gst_.buffer) {
    return nullptr;
  }

  const uint32_t pixel_bytes = width_ * height_ * 4;
  gst_buffer_extract(gst_.buffer, 0, pixels_.get(), pixel_bytes);
  return reinterpret_cast<const uint8_t*>(pixels_.get());
}

// Creats a video pipeline using playbin.
// $ playbin uri=<file> video-sink="videoconvert ! video/x-raw,format=RGBA !
// fakesink"
bool GstVideoPlayer::CreatePipeline() {
  gst_.pipeline = gst_pipeline_new("pipeline");
  if (!gst_.pipeline) {
    std::cerr << "Failed to create a pipeline" << std::endl;
    return false;
  }
  gst_.playbin = gst_element_factory_make("playbin", "playbin");
  if (!gst_.playbin) {
    std::cerr << "Failed to create a source" << std::endl;
    return false;
  }
  gst_.video_convert = gst_element_factory_make("videoconvert", "videoconvert");
  if (!gst_.video_convert) {
    std::cerr << "Failed to create a videoconvert" << std::endl;
    return false;
  }
  gst_.video_sink = gst_element_factory_make("fakesink", "videosink");
  if (!gst_.video_sink) {
    std::cerr << "Failed to create a videosink" << std::endl;
    return false;
  }
  gst_.output = gst_bin_new("output");
  if (!gst_.output) {
    std::cerr << "Failed to create an output" << std::endl;
    return false;
  }
  gst_.bus = gst_pipeline_get_bus(GST_PIPELINE(gst_.pipeline));
  if (!gst_.bus) {
    std::cerr << "Failed to create a bus" << std::endl;
    return false;
  }
  gst_bus_set_sync_handler(gst_.bus, HandleGstMessage, this, NULL);

  // Sets properties to fakesink to get the callback of a decoded frame.
  // It keeps no frame of its own: the hardware decoder has only a few.
  g_object_set(G_OBJECT(gst_.video_sink), "sync", TRUE, "qos", FALSE,
               "enable-last-sample", FALSE, NULL);
  g_object_set(G_OBJECT(gst_.video_sink), "signal-handoffs", TRUE, NULL);
  g_signal_connect(G_OBJECT(gst_.video_sink), "handoff",
                   G_CALLBACK(HandoffHandler), this);
  gst_bin_add_many(GST_BIN(gst_.output), gst_.video_convert, gst_.video_sink,
                   NULL);

  // Takes the hardware decoder's frames as they are (videoconvert passes
  // them through), and converts anything else to RGBA.
  std::string formats = "video/x-raw,format=RGBA";
  if (HardwareDecoding()) {
    formats = std::string("video/x-raw(") + kDroidQueueBuffer + "); " + formats;
  }
  auto* caps = gst_caps_from_string(formats.c_str());
  auto link_ok =
      gst_element_link_filtered(gst_.video_convert, gst_.video_sink, caps);
  gst_caps_unref(caps);
  if (!link_ok) {
    std::cerr << "Failed to link elements" << std::endl;
    return false;
  }

  auto* sinkpad = gst_element_get_static_pad(gst_.video_convert, "sink");
  auto* ghost_sinkpad = gst_ghost_pad_new("sink", sinkpad);
  gst_pad_set_active(ghost_sinkpad, TRUE);
  gst_element_add_pad(gst_.output, ghost_sinkpad);
  gst_object_unref(sinkpad);

  // Sets properties to playbin.
  g_object_set(gst_.playbin, "uri", uri_.c_str(), NULL);
  g_object_set(gst_.playbin, "video-sink", gst_.output, NULL);
  g_signal_connect(gst_.playbin, "deep-element-added",
                   G_CALLBACK(OnElementAdded), NULL);
  gst_bin_add_many(GST_BIN(gst_.pipeline), gst_.playbin, NULL);

  return true;
}

bool GstVideoPlayer::Preroll() {
  if (!gst_.playbin) {
    return false;
  }

  auto result = gst_element_set_state(gst_.pipeline, GST_STATE_PAUSED);
  if (result == GST_STATE_CHANGE_FAILURE) {
    std::cerr << "Failed to change the state to PAUSED" << std::endl;
    return false;
  }

  // Waits until the state becomes GST_STATE_PAUSED, or gives up.
  if (result == GST_STATE_CHANGE_ASYNC) {
    GstState state;
    result =
        gst_element_get_state(gst_.pipeline, &state, NULL, kPrerollTimeout);
    if (result == GST_STATE_CHANGE_ASYNC) {
      std::cerr << "No first frame within the time limit" << std::endl;
      return false;
    }
    if (result == GST_STATE_CHANGE_FAILURE) {
      std::cerr << "Failed to get the current state" << std::endl;
      return false;
    }
  }
  return true;
}

void GstVideoPlayer::DestroyPipeline() {
  if (gst_.video_sink) {
    g_object_set(G_OBJECT(gst_.video_sink), "signal-handoffs", FALSE, NULL);
  }

  if (gst_.pipeline) {
    gst_element_set_state(gst_.pipeline, GST_STATE_NULL);
  }

  if (gst_.buffer) {
    gst_buffer_unref(gst_.buffer);
    gst_.buffer = nullptr;
  }
  gst_buffer_replace(&shown_buffer_, nullptr);

  if (gst_.bus) {
    gst_object_unref(gst_.bus);
    gst_.bus = nullptr;
  }

  if (gst_.pipeline) {
    gst_object_unref(gst_.pipeline);
    gst_.pipeline = nullptr;
  }

  if (gst_.playbin) {
    gst_.playbin = nullptr;
  }

  if (gst_.output) {
    gst_.output = nullptr;
  }

  if (gst_.video_sink) {
    gst_.video_sink = nullptr;
  }

  if (gst_.video_convert) {
    gst_.video_convert = nullptr;
  }
}

std::string GstVideoPlayer::ParseUri(const std::string& uri) {
  if (gst_uri_is_valid(uri.c_str())) {
    return uri;
  }

  auto* filename_uri = gst_filename_to_uri(uri.c_str(), NULL);
  if (!filename_uri) {
    std::cerr << "Faild to open " << uri.c_str() << std::endl;
    return uri;
  }
  std::string result_uri(filename_uri);
  g_free(filename_uri);

  return result_uri;
}

void GstVideoPlayer::GetVideoSize(int32_t& width, int32_t& height) {
  if (!gst_.pipeline || !gst_.video_sink) {
    std::cerr
        << "Failed to get video size. The pileline hasn't initialized yet.";
    return;
  }

  auto* sink_pad = gst_element_get_static_pad(gst_.video_sink, "sink");
  if (!sink_pad) {
    std::cerr << "Failed to get a pad";
    return;
  }

  auto* caps = gst_pad_get_current_caps(sink_pad);
  if (!caps) {
    std::cerr << "Failed to get caps" << std::endl;
    gst_object_unref(sink_pad);
    return;
  }

  auto* structure = gst_caps_get_structure(caps, 0);
  if (!structure) {
    std::cerr << "Failed to get a structure" << std::endl;
    gst_caps_unref(caps);
    gst_object_unref(sink_pad);
    return;
  }

  gst_structure_get_int(structure, "width", &width);
  gst_structure_get_int(structure, "height", &height);

  GstCapsFeatures* features = gst_caps_get_features(caps, 0);
  uses_egl_images_ =
      features && gst_caps_features_contains(features, kDroidQueueBuffer);

  gst_caps_unref(caps);
  gst_object_unref(sink_pad);
}

// static
void GstVideoPlayer::HandoffHandler(GstElement* fakesink, GstBuffer* buf,
                                    GstPad* new_pad, gpointer user_data) {
  auto* self = reinterpret_cast<GstVideoPlayer*>(user_data);
  auto* caps = gst_pad_get_current_caps(new_pad);
  auto* structure = gst_caps_get_structure(caps, 0);

  int width;
  int height;
  gst_structure_get_int(structure, "width", &width);
  gst_structure_get_int(structure, "height", &height);
  gst_caps_unref(caps);
  if (width != self->width_ || height != self->height_) {
    self->width_ = width;
    self->height_ = height;
    if (!self->uses_egl_images_) {
      self->pixels_.reset(new uint32_t[width * height]);
    }
    std::cout << "Pixel buffer size: width = " << width
              << ", height = " << height << std::endl;
  }

  std::lock_guard<std::shared_mutex> lock(self->mutex_buffer_);
  if (self->gst_.buffer) {
    gst_buffer_unref(self->gst_.buffer);
    self->gst_.buffer = nullptr;
  }
  self->gst_.buffer = gst_buffer_ref(buf);
  self->stream_handler_->OnNotifyFrameDecoded();
}

// static
GstBusSyncReply GstVideoPlayer::HandleGstMessage(GstBus* bus,
                                                 GstMessage* message,
                                                 gpointer user_data) {
  switch (GST_MESSAGE_TYPE(message)) {
    case GST_MESSAGE_EOS: {
      auto* self = reinterpret_cast<GstVideoPlayer*>(user_data);
      std::lock_guard<std::mutex> lock(self->mutex_event_completed_);
      self->is_completed_ = true;
      break;
    }
    case GST_MESSAGE_WARNING: {
      gchar* debug;
      GError* error;
      gst_message_parse_warning(message, &error, &debug);
      g_printerr("WARNING from element %s: %s\n", GST_OBJECT_NAME(message->src),
                 error->message);
      g_printerr("Warning details: %s\n", debug);
      g_free(debug);
      g_error_free(error);
      break;
    }
    case GST_MESSAGE_ERROR: {
      gchar* debug;
      GError* error;
      gst_message_parse_error(message, &error, &debug);
      g_printerr("ERROR from element %s: %s\n", GST_OBJECT_NAME(message->src),
                 error->message);
      g_printerr("Error details: %s\n", debug);
      g_free(debug);
      g_error_free(error);
      break;
    }
    default:
      break;
  }

  gst_message_unref(message);

  return GST_BUS_DROP;
}
