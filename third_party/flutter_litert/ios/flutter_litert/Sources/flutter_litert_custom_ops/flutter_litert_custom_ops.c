#include "flutter_litert_custom_ops.h"

#if defined(__arm64__)
// Share the same implementation used by CocoaPods and desktop builds.
#define TFLITE_USE_LOCAL_HEADERS 1
#include "../../../../src/custom_ops/transpose_conv_bias.c"

static const void* volatile g_custom_ops_anchor;

void FlutterLitertRetainCustomOps(void) {
  g_custom_ops_anchor =
      (const void*)&TfLiteFlutter_RegisterConvolution2DTransposeBias;
}
#else
// The published SPM simulator artifacts currently contain arm64 slices only.
void FlutterLitertRetainCustomOps(void) {}
#endif
