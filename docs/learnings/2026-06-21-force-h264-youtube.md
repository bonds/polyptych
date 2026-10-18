# Force H.264 for YouTube downloads on M2

**Date:** 2026-06-21 (commits `3bbf5b0`, `24f1a30`)

## Symptom

YouTube served VP9/AV1 by default, and software decoding those on an M2 was
too slow (the M2 has no hardware decoder for VP9/AV1).

## What worked

Pin the yt-dlp format to H.264 (which the M2 decodes fine, and which pairs
with `hwdec=no`):

```
bestvideo[height<=1080][vcodec^=avc1]+bestaudio[ext=m4a]/best[height<=1080]
```

Later hardened by checking the cached file's codec on a cache hit and
re-downloading if it isn't h264 (`24f1a30`).

**Lesson:** pick the codec the machine can actually decode. Don't rely on
the site's default stream.
