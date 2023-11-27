# Containerizing AOM AV1 and encoding videos with FFmpeg in an Node.js app

![AV1 Docker FFmpeg](av1_docker_ffmpeg.png)

This blog post has been originally posted at [dev.to/sw360cab](https://dev.to/sw360cab/containerizing-aom-av1-and-encoding-videos-with-ffmpeg-in-an-nodejs-app-1lh2)`

I have recently had the opportunity to work and study the AV1 Codec by AOM ([Alliance for Open Media](https://aomedia.org/)). It is the state-of-the-art video codec for manipulating videos today, and it is stunning how it is able to compress videos producing files with reduced size and a pretty much untouched quality (I will later do a small comparison with the ancestor AVC/H.264 by MPEG).
And since I am a big, better huge fan of FFmpeg I cannot step back from compiling a fully working FFmpeg binary within a container image. Later I will describe how I achieved that and how it can be used within a Node.js application.

You can check out the source code in [GitHub](https://github.com/sw360cab/docker-ffmpeg-av1).

## A bit of history

The creation of the AOM group is a sort of strong answer to the last video codecs standardized by the MPEG group.
Starting from the end of the previous millennium, the standardization of audio and video formats and codecs was dominated by the MPEG group, with the huge success of the MP3 standard (aka MPEG-1 layer 3) for audio, followed by the other great success of the AVC codec for videos, created jointly with ITU.T (which internally nominated the standard H.264 and used to commonly refer to it, instead of AVC).

![Say H264 one more time.](https://i.imgflip.com/86pnr8.jpg)

The licensing model of codecs by MPEG started to have some critics already with AVC, but it reached its peak with the upcoming HEVC standard (aka H.265) whose licensing model appeared unacceptable for many players of the video & internet industry led by Google.  
The result was the creation of the new standardization group Alliance for Open Media (AOM), whose main focus was creating the next optimize royalty-free video codec: AV1.

![AOM AV1 vs MPEG HEVC](https://i.imgflip.com/86pqz3.jpg)

## Containerizing AV1 with FFmpeg in a Docker IM

Evaluating the performance of the AV1 codec would be almost impossible without leveraging FFmpeg, the state-of-the-art and reference software to manipulate, compress and low-level edit of videos, the software is also the reference for big Video streaming platforms like Netflix, Disney+ and YouTube.

[FFmpeg su X: "Your weekly reminder that FFmpeg powers all online video - Youtube, Facebook, Instagram, Disney+, Netflix etc etc, all run FFmpeg underneath"](https://twitter.com/FFmpeg/status/1710440696941809868)
{% twitter 1710440696941809868 %}

And creating a portable solution would be not possible as well without building a Container Image in Docker which allows pin versions of libraries and reuse, update and run them without taking care to the current system configuration.

## Dockerfile for FFmpeg + AV1

To achieve a fully-functional FFmpeg application from Docker, let's start from an Ubuntu Image and then build on top of it all the single codecs and libraries.
In this case it is very useful to deal with a Docker Image since versions of libraries and download url counterparts can be accumulated at the beginning of the Dockerfile and eventually overwritten via build arguments.

Most libraries during compilation and build, will write information that FFmpeg compilation step will then retrieve using `pkg-config`.
The following codecs libraries will be downloaded and compiled statically, each reporting in parenthesis the flag to enable it during FFmpeg _building from source_ step.

* libfreetype (--enable-libfreetype)
* libx264 (--enable-libx264)
* libx265 (--enable-libx264)
* libfdk-aac (--enable-libfdk-aac)
* liblame-mp3 (--enable-libmp3lame)
* libaom (--enable-libaom)
* libsvtav1 (--enable-libsvtav1)

For AV1 both `libaom` and `libsvtav1` will be built. However according to FFmpeg documentation about AV1, SVT-AV1 is now the reference for [AV1 encoding](https://trac.ffmpeg.org/wiki/Encode/AV1#SVT-AV1)
> SVT-AV1 was adopted by AOMedia as the basis for the future development of AV1 as well as future codec efforts.

After all these steps in the Dockerfile, it is possible to proceed with the download and build of Ffmpeg from source code (I picked a pinned version from a git tag: 5.1), enabling with flags the previously compiled codecs. As for the other libraries compiled in previous steps, the _configure, make, make install_ will happen in a single `RUN` step.

```bash
RUN git clone --depth 1 --branch n5.1 https://git.ffmpeg.org/ffmpeg.git ffmpeg && cd ffmpeg && \
  PKG_CONFIG_PATH="$BUILD_PREFIX/lib/pkgconfig" ./configure \
  --prefix="$BUILD_PREFIX" \
  --pkg-config-flags="--static" \
  --extra-cflags="-I$BUILD_PREFIX/include" \
  --extra-ldflags="-L$BUILD_PREFIX/lib -L$BUILD_PREFIX/lib64" \
  --extra-libs="-lpthread -lm -lz" \
  --extra-ldexeflags="-static" \
  --bindir="$HOME/bin" \
  --enable-gpl \
  --disable-shared \
  --enable-static \
  --enable-nonfree \
  --disable-libfreetype \
  --enable-libfdk-aac \
  --enable-libmp3lame \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libaom \
  --enable-libsvtav1 \
  --disable-doc \
  --disable-podpages \
  --disable-debug \
  && \
  make -j 10 && \
  make install
```

### Note for SVT-AV1

In order to add the compiled `libsvtav1` library to the FFmpeg build, some patches provided by libsvtav1 library itself should be applied to the FFmpeg source code, so an additional `RUN` step has been added.

```bash
RUN git clone --depth 1 --branch n5.1 https://git.ffmpeg.org/ffmpeg.git ffmpeg && \
  git config --global user.email "media@minimalgap.com" && \
  git -C ffmpeg am $BUILD_PREFIX/ffmpeg_plugin/n5.1/*.patch
```

The `output` of this image is a layer with a compiled and working FFmpeg (and FFprobe) binary ready to use.

## Using FFmpeg binary

Now that we have a working Docker image, we can build on top of that other applications that can easily leverage FFmpeg (or its sibling FFprobe) binary.
Again we will take advantage of Docker in particular of `multi-stage build`.

I've created a basic `Node.js` application whose purpose is to generate a compressed video and place it into a specific folder with
`.mp4` extension starting from command line and an input video and specifying a codec among AV1, H.264 and HEVC.
> Of course this application is a POC and can be expanded with any other possible option.

The Dockerfile for the Node.js will include the FFmpeg binary via the `COPY` directive. I have a used a very common pattern that Docker enables using multi stage build: the `COPY` directive has a peculiarity clearly stated in the official Dockerfile reference doc:
> COPY accepts a flag --from=`<name>` that can be used to set the source location to a previous build stage (created with FROM .. AS `<name>`) that will be used instead of a build context sent by the user. In case a build stage with a specified name can't be found an image with the same name is attempted to be used instead.

I have also included a [docker-compose version](https://github.com/sw360cab/docker-ffmpeg-av1/blob/master/docker-compose.yml) where both the images can be built in a single shot.

### Gotcha - BUILDKIT

Since `BuildKit` is enabled by default in the newer versions of Docker Engine, when building a compose file with multiple services it is not guaranteed that the order of appearance in the compose file is respected because of `BuildKit` itself attempting to optimize the build process.

To overcome this problem it is possible to:

* Disable BuildKit

```bash
DOCKER_BUILDKIT=0 docker-compose build
```

* Alternatively build `ffmpeg` image separately and then the remaining services

```bash
  docker-compose build ffmpeg
  docker-compose build
```

## AOM AV1 vs MPEG HEVC [aka H.265] vs MPEG AVC [aka H.264]

The application previously created and build is able to encode videos from command line, for sake of simplicity it will allow only two options:

* **-i** for input file path
* **-codec** for video codec to be picked among _av1, hevc, h264_

Again to keep it simple each audio will be encoded using `HE_AAC` audio codec.  
Whereas for each video codec there is an hardcoded configuration:

* for **AV1**: `-c:v libsvtav1 -pix_fmt yuv420p -crf 45 -preset 7 -svtav1-params fast-decode=1:film-grain=7:tune=0`
* for **HEVC**: `libx265 -pix_fmt yuv420p -profile:v main -preset slower -crf 27`
* for **H.264**: `libx264 -pix_fmt yuv420p -profile:v high -level 4.1 -preset slower -crf 22 -tune film`

The purpose here is just to provide a quick way to compare results of videos processed with each codec both visually and with respect to file size and CPU time to process a video.

### Notes on CRF

`Constant Rate Factor` (CRF) is a rate control mode that allows the encoder to attempt to achieve a certain output quality for the whole file when output file size is of less importance.

* for **AV1** [_libsvtav1_]: the valid CRF value range is 0-63, with the default being 50. Lower values correspond to higher quality and greater file size
* for **HEVC** [_libx265_]: the mode works exactly the same as in `libx264`, except that maximum value is always 51, even with 10-bit support. The default is 28, and it should visually correspond to _libx264_ video at CRF 23
* for **H.264** [_libx264_]: The range of the CRF scale is 0–51, where 0 is lossless (for 8 bit only, for 10 bit use -qp 0), 23 is the default, and 51 is worst quality possible

Making a deep comparison among the results achieved from the 3 different codecs is out of the scope of this post. It will also be unfair, since all the three codecs have plenty of options and it's not easy to achieve three identical and fair configurations to make a real comparisons.
Moreover the results would be strongly influenced by the input video and its codecs configuration.

I will here highlight the main feedbacks so far:

* _AV1_ is in general the slower to process but it produces the smallest sized output file.
* _H.264/AVC_ is the fastest one but it produces the output file with the biggest size.
* _HEVC_ is as slow as AV1 but it tends to create bigger sized files (this is a guess because it is strongly influenced by codec configuration)
* _AV1_ apparently produce amazingly high quality video even if compression is at a very high rate

## Test Video 1: small sized video

![Video 1](https://res.cloudinary.com/practicaldev/image/fetch/s--B8KRUCiX--/c_limit%2Cf_auto%2Cfl_progressive%2Cq_auto%2Cw_800/https://dev-to-uploads.s3.amazonaws.com/uploads/articles/x2dh2q4z5eaz40ougj9j.png)

* [Source Video](https://github.com/sw360cab/docker-ffmpeg-av1/raw/master/data/sample_0.mp4)
* Video codec: AVC/H264
* Duration: ~ 20 s
* File size: 54 MB
* Ffprobe Output:

> Duration: 00:00:18.88, start: 0.000000, bitrate: 23842 kb/s  
Stream #0:0: Video: h264 (High) (avc1 / 0x31637661), yuvj420p(pc, bt709, progressive), 1920x1080, 23673 kb/s, 25 fps, 25 tbr, 25k tbn (default)  
Stream #0:1: Audio: aac (LC) (mp4a / 0x6134706D), 48000 Hz, stereo, fltp, 127 kb/s (default)

* HW: Mac Book Pro 2018, CPU Intel i7 2,6 GHz 6-cores, RAM 32 GB

| Codec | File Size | CPU Time |
| --- | --- | --- |
| AV1 | 2.5 MB | 38 s |
| HEVC | 5.7 MB | 464 s |
| H.264 | 13.3 MB | 24 s |

* HW: Linux Station, CPU Intel Xeon Gold 6230 2,1 GHz 8-cores, RAM 16 GB

| Codec | File Size | CPU Time |
| --- | --- | --- |
| AV1 | 2.5 MB | 58 s |
| HEVC | 5.7 MB | 328 s |
| H.264 | 13.3 MB | 40 s |

## Test Video 2: raw video

![Video 2](https://res.cloudinary.com/practicaldev/image/fetch/s--D59_kYZv--/c_limit%2Cf_auto%2Cfl_progressive%2Cq_auto%2Cw_800/https://dev-to-uploads.s3.amazonaws.com/uploads/articles/5kay0zcwp30gmu8jkmc3.png)

* [Source Video](https://media.xiph.org/video/derf/ElFuente/Netflix_BoxingPractice_4096x2160_60fps_10bit_420.y4m)
* Video codec: N/A - Raw video
* Duration: ~ 4.30 min
* File size: 6.3 GB
* Ffprobe Output:

> Duration: 00:00:04.23, start: 0.000000, bitrate: 12740202 kb/s  
Stream #0:0: Video: rawvideo, yuv420p10le(progressive), 4096x2160, SAR 1:1 DAR 256:135, 60 fps, 60 tbr, 60 tbn

* HW: Mac Book Pro 2018, CPU Intel i7 2,6 GHz 6-cores, RAM 32 GB

| Codec | File Size | CPU Time |
| --- | --- | --- |
| AV1 | 3 MB | 136 s |
| HEVC | 4 MB | 780 s |
| H.264 | 15.4 MB| 85 s |

* HW: Linux Station, CPU Intel Xeon Gold 6230 2,1 GHz 8-cores, RAM 16 GB

| Codec | File Size | CPU Time |
| --- | --- | --- |
| AV1 | 3 MB | 159 s |
| HEVC | 4 MB | 625 s |
| H.264 | 15.4 MB| 84 s |

## Recap

As said the purpose of these compression tests is not a deep comparison among codec results and parameters.
From the previous tests I can state that AV1 is giving back strongly compressed videos with a long processing duration compared to H.264. It is also giving similar results to HEVC but with a faster compression time with and comparable or smaller sized videos.  
Compared to H.264/AVC, the codec AV1 is taking an inversely proportional CPU time compared to order of magnitude in terms of reduced size.

Check out the source code in [GitHub](https://github.com/sw360cab/docker-ffmpeg-av1).

## References

* [sw360cab/docker-ffmpeg-av1: Containerized fully static compiled FFmpeg binary with AOM AV1 Codec](https://github.com/sw360cab/docker-ffmpeg-av1)
* [Encode/H.264 – FFmpeg](https://trac.ffmpeg.org/wiki/Encode/H.264)
* [Encode/H.265 – FFmpeg](https://trac.ffmpeg.org/wiki/Encode/H.265)
* [Encode/AV1 STV-AV1 – FFmpeg](https://trac.ffmpeg.org/wiki/Encode/AV1#SVT-AV1)
* [AV1 Video Codec | Alliance for Open Media](https://aomedia.org/av1/)
* [Xiph.org :: Derf's Test Media Collection](https://media.xiph.org/video/derf/)
