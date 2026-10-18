# Hardware decode was slower than software on M2 (1080p H.264)

**Date:** 2026-06-21 (commits `d9757ce` added it, `ab8151b` reverted it)

## Symptom

`hwdec=videotoolbox-copy` dropped the frame rate to 7–9fps.

## Cause

`videotoolbox-copy` copies the decoded frame from GPU to CPU memory so it can
be handed to the software renderer. The GPU→CPU synchronisation stalls the
render loop; the copy costs more than it saves.

## What worked

`hwdec=no` — pure software decode with FFmpeg. On an M2, software decode of
1080p H.264 is faster than the hardware-decode-plus-copy path.

**Lesson:** "hardware decode" isn't automatically faster. With a software
renderer (`vo=libmpv`, SW backend) the GPU→CPU copy can cost more than just
decoding on the CPU. Measure both.
