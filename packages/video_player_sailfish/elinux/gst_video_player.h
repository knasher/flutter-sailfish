// Copyright 2021 Sony Group Corporation. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef PACKAGES_VIDEO_PLAYER_VIDEO_PLAYER_ELINUX_GST_VIDEO_PLAYER_H_
#define PACKAGES_VIDEO_PLAYER_VIDEO_PLAYER_ELINUX_GST_VIDEO_PLAYER_H_

#include <gst/gst.h>

#include <memory>
#include <mutex>
#include <shared_mutex>
#include <string>

#include "video_player_stream_handler.h"

class GstVideoPlayer {
 public:
  GstVideoPlayer(const std::string& uri,
                 std::unique_ptr<VideoPlayerStreamHandler> handler);
  ~GstVideoPlayer();

  static void GstLibraryLoad();
  static void GstLibraryUnload();

  bool Init();
  bool Play();
  bool Pause();
  bool Stop();
  bool SetVolume(double volume);
  bool SetPlaybackRate(double rate);
  void SetAutoRepeat(bool auto_repeat) { auto_repeat_ = auto_repeat; };
  bool SetSeek(int64_t position);
  int64_t GetDuration();
  int64_t GetCurrentPosition();
  const uint8_t* GetFrameBuffer();
  // Whether frames come from the hardware decoder as Android graphics
  // buffers, shown through GetEGLImage, rather than as RGBA pixels for
  // GetFrameBuffer. Known once Init has succeeded.
  bool UsesEGLImages() const { return uses_egl_images_; }
  // An EGLImage of the latest frame on |egl_display|, or null. The frame is
  // kept from the decoder until the next one is taken. Destroy the image with
  // DestroyEGLImage once it is bound to a texture.
  void* GetEGLImage(void* egl_display);
  static void DestroyEGLImage(void* egl_display, void* egl_image);
  int32_t GetWidth() const { return width_; };
  int32_t GetHeight() const { return height_; };

 private:
  struct GstVideoElements {
    GstElement* pipeline;
    GstElement* playbin;
    GstElement* video_convert;
    GstElement* video_sink;
    GstElement* output;
    GstBus* bus;
    GstBuffer* buffer;
  };

  static void HandoffHandler(GstElement* fakesink, GstBuffer* buf,
                             GstPad* new_pad, gpointer user_data);
  static GstBusSyncReply HandleGstMessage(GstBus* bus, GstMessage* message,
                                          gpointer user_data);
  std::string ParseUri(const std::string& uri);
  bool CreatePipeline();
  void DestroyPipeline();
  bool Preroll();
  void GetVideoSize(int32_t& width, int32_t& height);

  GstVideoElements gst_;
  std::string uri_;
  std::unique_ptr<uint32_t[]> pixels_;
  int32_t width_;
  int32_t height_;
  double volume_ = 1.0;
  double playback_rate_ = 1.0;
  // In milliseconds.
  int64_t last_position_ = 0;
  bool mute_ = false;
  bool auto_repeat_ = false;
  bool is_completed_ = false;
  std::mutex mutex_event_completed_;
  std::shared_mutex mutex_buffer_;
  std::unique_ptr<VideoPlayerStreamHandler> stream_handler_;
  bool uses_egl_images_ = false;
  // The frame the texture shows, kept while the GPU may still read it.
  GstBuffer* shown_buffer_ = nullptr;
};

#endif  // PACKAGES_VIDEO_PLAYER_VIDEO_PLAYER_ELINUX_GST_VIDEO_PLAYER_H_
