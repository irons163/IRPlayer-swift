# Fisheye UI fixture

`SPMDemo/SPMDemo/fisheye-ui-test.mp4` repeats the existing `fisheye-demo.mp4`
ten times by stream copy. It is 60 seconds, 544 × 544 H.264, 5 fps, 300 frames,
with no audio. No frame is re-encoded. Its longer duration accommodates slow
XCTest gestures and screenshot collection without sampling a retained EOF
frame. The DEBUG-only `IRPLAYER_UI_TEST_LONG_FISHEYE=1` launch option selects it;
ordinary demo playback continues to use the original six-second clip.

The Xcode synchronized app folder includes this resource automatically. CI
consumes the checked-in fixture and does not need to install FFmpeg. To regenerate
into a new path (the script refuses overwrites):

```sh
bash Scripts/ci/generate-fisheye-ui-fixture.sh /tmp/fisheye-ui-regenerated.mp4
```

Generated with local FFmpeg 8.1.1, separate from the SDK's bundled FFmpeg.
Container metadata can vary with the generator version. Verification compared
SHA-256 hashes of every encoded packet using `ffprobe -show_packets
-show_data_hash sha256`: the 300 output packets equal the 30 source packets
repeated exactly ten times. Duration/frame count were also verified with
`ffprobe -show_entries format=duration:stream=nb_frames,r_frame_rate`.

Recorded file SHA-256:

- Original: `a6fd525d932330c6d6da61a8f3132284f8673f8713e33397493512e18bf8ae7e`
- UI fixture: `ffbf01350064e906813c81fb3891d426717e1c0e917728d957b56416bff517f7`

UI tests require the displayed duration to be `01:00` and reject `Finished`
after the sampling window. All existing 24-sample black-flash and temporal
change thresholds are unchanged. Natural discontinuities at the six-second
repeat boundaries do not excuse a frozen displayed frame.
