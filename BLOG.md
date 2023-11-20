# Containerizing AOM AV1 and encoding videos with FFmpeg in an Node.js app

I have recently had the opportunity to work and study the AV1 Codec by AOM ([Alliance for Open Media](https://aomedia.org/)). It is the state-of-the-art video codec for manipulating videos today, and it is stunning how it is able to compress videos with a reduced file size and a pretty much  untouched quality (I will later do a small comparison with the ancestor AVC/H.264 by MPEG).
And since I am a big, better huge fan of FFmpeg I cannot step back from compiling a fully working FFmpeg binary within a container image. Later I will describe how I achieved that and how it can be used within a Node.js application.

You can check out code in [GitHub](https://github.com/sw360cab/docker-ffmpeg-av1).

## A bit of history

The creation of the AOM group is a sort of strong answer to the last video codecs standardized by the MPEG group.
Starting from the end of the previous millennium, the standardization of audio and video formats and codecs was dominated by the MPEG group, with the huge success of the MP3 standard (aka MPEG1 layer 3) for audio, followed by the other great success of the AVC codec for videos, created jointly with ITU.T (which internally nominated the standard H.264 and used to commonly refer to it, instead of AVC).

![Say H264 one more time.](https://i.imgflip.com/86pnr8.jpg)

The licensing model of codecs by MPEG started to have some critics already with AVC but it reached its peak with the upcoming HEVC standard (aka H.265) whose licensing model appeared unacceptable for many players of the video & internet industry led by Google.  
The result was the creation of the new standardization group Alliance for Open Media (AOM), whose main focus was creating the next optimize royalty-free video codec: AV1.

![AOM AV1 vs MPEG HEVC](https://i.imgflip.com/86pqz3.jpg)

## Containerizing AV1 with FFmpeg in a Docker IM

Evaluating the performance of the AV1 codec would be almost impossible without leveraging FFmpeg, this is the state-of-the-art and reference software to manipulate, compress and low-level edit of videos, the software is also the reference for big Video streaming platforms like Netflix, Disney+ and YouTube.

[FFmpeg su X: "Your weekly reminder that FFmpeg powers all online video - Youtube, Facebook, Instagram, Disney+, Netflix etc etc, all run FFmpeg underneath"](https://twitter.com/FFmpeg/status/1710440696941809868)
{% twitter 1497533289930063877 %}

And creating a portable solution would be not possible as well without building a Container Image in Docker which allows pin versions of libraries and reuse, update and run them without taking care to the current system configuration.

## Dockerfile for FFmpeg + AV1

To achieve a fully-functional FFmpeg application from Docker, let's start from an Ubuntu Image and then build on top of it all the single codecs and libraries.
In this case it is very useful to deal with a Docker Image since versions of libraries and download url counterparts can be accumulated at the beginning of the Dockerfile and eventually overwritten via build arguments.

Most libraries during compilation and build, will write information that FFmpeg compilation step will then retrieve using `pkg-config`.
The following codecs libraries will be downloaded and compiled statically, each reporting in parenthesis the flag to enable it during FFmpeg _building from source_ step.

* libass
* libfreetype (--enable-libfreetype)
* libx264 (--enable-libx264)
* libx265 (--enable-libx264)
* libfdk-aac (--enable-libfdk-aac)
* liblame-mp3 (--enable-libmp3lame)
* libaom (--enable-libaom)
* libsvtav1 (--enable-libsvtav1)

For AV1 both `libaom` and `libsvtav1` will be built. However according to FFmpeg documentation about AV1, SVT-AV1 is now the reference for [AV1 encoding](https://trac.ffmpeg.org/wiki/Encode/AV1#SVT-AV1)
> SVT-AV1 was adopted by AOMedia as the basis for the future development of AV1 as well as future codec efforts.
After all these steps in the Dockerfile, it is possible to proceed with the download and build of Ffmpeg from source code (I picked a pinned version from a git tag: 5.1), enabling with flags the previously compiled codecs. As for the other libraries compiled in previous steps, the configure, make, make install will happen in a single RUN step.

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

In order to add compiled libsvtav1 library to the Ffmpeg build, some patches provided by libsvtav1 library should be applied to the Ffmpeg source code, so an additional RUN step was added.

```bash
RUN git clone --depth 1 --branch n5.1 https://git.ffmpeg.org/ffmpeg.git ffmpeg && \
  git config --global user.email "media@minimalgap.com" && \
  git -C ffmpeg am $BUILD_PREFIX/ffmpeg_plugin/n5.1/*.patch
```

The `output` of this image is a layer with a compiled and working FFmpeg (and FFprobe) binary ready to use.

## Using FFmpeg binary

Now that we have a working Docker image, we can build on top of that other applications that can easily leverage FFmpeg (or its sibling FFprobe) binary.
Again we will take advantage of Docker in particular of Multistage build.

I've created a basic Node.js application whose purpose is to create a compressed video encoded with AV1 and place it in a specific folder with
`.mp4` extension starting from command line and an input video and specifying a codec among AV1, H.264 and HEVC.
> Of course this application is a POC and can be expanded with any other possible option.

The Dockerfile for the Node.js will include the FFmpeg binary via the COPY directive. I have a used a very common pattern that Docker enables using multi stage build: The COPY directive has a peculiarity clearly stated in the official Dockerfile reference doc:
> COPY accepts a flag --from=`<name>` that can be used to set the source location to a previous build stage (created with FROM .. AS `<name>`) that will be used instead of a build context sent by the user. In case a build stage with a specified name can't be found an image with the same name is attempted to be used instead.

I have also included a [docker-compose version](https://github.com/sw360cab/docker-ffmpeg-av1/blob/master/docker-compose.yml) where both the images can be built in a single shot.

### Gotcha - BUILDKIT

Since BUILDKIT is enabled by default in the newer versions of Docker Engine, when building a compose file with multiple services it is not guaranteed that the order of appearance in the compose file is respected because of BuildKit itself attempting to optimize builds.

To overcome this problem it is possible to:

* Disable BuildKit

```bash
DOCKER_BUILDKIT=0 docker-compose build
```

* Alternatively build `ffmpeg` image separately and then the rest

```bash
  docker-compose build ffmpeg
  docker-compose build
```

## AOM AV1 vs MPEG HEVC [aka H.265] vs MPEG AVC [aka H.264]

The application previously created and build is able to encode videos from command line, for sake of simplicity it will allow only two options:
“-i” for input file path [mandatory]
“-codec” for video codec to be picked among: av1, x265,x264 [optional default:AV1]

Again to keep it simple each audio will be encoded using HE_AAC audio codec. Whereas for each video codec there is an hardcoded configuration:

* for **AV1**: `-c:v libsvtav1 -pix_fmt yuv420p -crf 45 -preset 7 -svtav1-params fast-decode=1:film-grain=7:tune=0`
* for **HEVC**: `libx265 -pix_fmt yuv420p -profile:v main -preset slower -crf 27`
* for **H.264**: `libx264 -pix_fmt yuv420p -profile:v high -level 4.1 -preset slower -crf 22 -tune film`

The purpose of this is just to provide a quick way to compare visual results of videos processed with each codec in contrast with file size and processing time.

### Notes on CRF

Constant Rate Factor (CRF) is a rate control mode that allows the encoder to attempt to achieve a certain output quality for the whole file when output file size is of less importance.

* for **AV1**: the valid CRF value range is 0-63, with the default being 50. Lower values correspond to higher quality and greater file size
* for **HEVC**: the mode works exactly the same as in x264, except that maximum value is always 51, even with 10-bit support. The default is 28, and it should visually correspond to libx264 video at CRF 23
* for **H.264**: The range of the CRF scale is 0–51, where 0 is lossless (for 8 bit only, for 10 bit use -qp 0), 23 is the default, and 51 is worst quality possible

Making a deep comparison among the results achieved from the 3 different codecs is out of the scope of this post. It will also be unfair, since all the three codecs have plenty of options and it's not easy to achieve three identical and fair configurations to make fair comparisons.
Moreover the results would be strongly influenced by the input video and its codecs configuration.

I will here highlight the main feedbacks so far:

* AV1 is in general the slower to process but it produce the smallest sized output file.
* H.264/AVC is the fastest one but it produce the output file with the biggest size.
* HEVC is as slow as AV1 but it tends to create bigger sized files (this is a guess because it is strongly influenced by codec configuration)
* AV1 apparently produce amazingly high quality video even if compression is at a very high rate

## Test Video 1: small sized video

Image
[Source Video](https://github.com/sw360cab/docker-ffmpeg-av1/raw/master/data/sample_0.mp4)

* Video codec: AVC/H264
* Duration: ~ 20 s
* File size: 54 MB
* Ffprobe Output:

> Duration: 00:00:18.88, start: 0.000000, bitrate: 23842 kb/s  
Stream #0:0[0x1](eng): Video: h264 (High) (avc1 / 0x31637661), yuvj420p(pc, bt709, progressive), 1920x1080, 23673 kb/s, 25 fps, 25 tbr, 25k tbn (default)  
Stream #0:1[0x2](eng): Audio: aac (LC) (mp4a / 0x6134706D), 48000 Hz, stereo, fltp, 127 kb/s (default)

| Codec | File Size | Processing duration |
| --- | --- | --- |
| AV1 | 2.5 MB | 38 s |
| HEVC | 5.7 MB | 464 s |
| H.264 | 13.3 MB | 24 s |

## Test Video 2: raw video

Image
[Source Video](https://media.xiph.org/video/derf/ElFuente/Netflix_BoxingPractice_4096x2160_60fps_10bit_420.y4m)

Image

* Video codec: rawvideo
* Duration: ~ 4.30 min
* File size: 6.3 GB
* Ffprobe Output:

> Duration: 00:00:04.23, start: 0.000000, bitrate: 12740202 kb/s  
Stream #0:0: Video: rawvideo, yuv420p10le(progressive), 4096x2160, SAR 1:1 DAR 256:135, 60 fps, 60 tbr, 60 tbn

| Codec | File Size | Processing duration |
| --- | --- | --- |
| AV1 | 3 MB | 136 s |
| HEVC | 4 MB | 780 s |
| H.264 | 15.4 MB| 85 s |

## Recap

As said the purpose of these is not a deep comparison among codec results and parameters.
From the previous test I can say that AV1 is giving back strongly compressed videos with a long processing duration compared to H.264. It is also giving similar results to HEVC but with a faster compression time with bigger sized videos.
Compared to H.264/AVC, the codec AV1 is taking an inversely proportional processing duration compared to order of magnitude in terms of reduced size.

Check out source code in [GitHub](https://github.com/sw360cab/docker-ffmpeg-av1).

## References

* [sw360cab/docker-ffmpeg-av1: Containerized fully static compiled FFmpeg binary with AOM AV1 Codec](https://github.com/sw360cab/docker-ffmpeg-av1)
* [Encode/H.264 – FFmpeg](https://trac.ffmpeg.org/wiki/Encode/H.264)
* [Encode/H.265 – FFmpeg](https://trac.ffmpeg.org/wiki/Encode/H.265)
* [Encode/AV1 STV-AV1 – FFmpeg](https://trac.ffmpeg.org/wiki/Encode/AV1#SVT-AV1)
* [AV1 Video Codec | Alliance for Open Media](https://aomedia.org/av1/)
* [Xiph.org :: Derf's Test Media Collection](https://media.xiph.org/video/derf/)
