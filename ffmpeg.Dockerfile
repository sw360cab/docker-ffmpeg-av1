FROM ubuntu:22.04 as ffmpeg-exec
LABEL maintainer="Sergio Matone"

ENV BUILD_PREFIX=/root/ffmpeg-build
ENV FREETYPE freetype-2.12.1
ENV ASS libass-0.17.1
ENV X265 x265_3.5
ENV FDKAAC fdk-aac-2.0.2
ENV LAMEMP3 lame-3.100

# Define the download URLs for the dependency source code
ENV FREETYPE_URL=https://sourceforge.net/projects/freetype/files/freetype2/2.12.1/${FREETYPE}.tar.gz
ENV ASS_URL=https://github.com/libass/libass/archive/0.17.1/${ASS}.tar.gz
ENV X264_URL=https://code.videolan.org/videolan/x264/-/archive/stable/x264-stable.tar.gz
ENV X265_URL=https://bitbucket.org/multicoreware/x265_git/downloads/${X265}.tar.gz
ENV FDKAAC_URL=https://github.com/mstorsjo/fdk-aac/archive/v2.0.2/${FDKAAC}.tar.gz
ENV LAMEMP3_URL=https://downloads.sourceforge.net/project/lame/lame/3.100/${LAMEMP3}.tar.gz

## install basic libraries for compiling and codecs
RUN apt update && apt install -y --no-install-recommends \
  git \
  yasm \
  nasm \
  pkg-config \ 
  autoconf \
  automake \
  build-essential \
  cmake \
  software-properties-common \
  wget \
  libtool \
  libgnutls28-dev \
  libfribidi-dev \
  libharfbuzz-dev \
  libnuma-dev \
  libunistring-dev \
  && rm -rf /var/lib/apt/lists/*

## manually compile codecs libraries

# # libfreetype
# RUN wget -qO- ${FREETYPE_URL} | tar xfvz - && \
#   cd ${FREETYPE} && \
#   PKG_CONFIG_PATH="$BUILD_PREFIX/lib/pkgconfig/" LDFLAGS="-L$BUILD_PREFIX/lib" \
#     CPPFLAGS="-I$BUILD_PREFIX/include" ./configure \
#     --disable-shared \
#     --enable-static \
#     --disable-dependency-tracking \
#     --prefix=$BUILD_PREFIX && \
#   make && \
#   make install

# libfreetype2
RUN wget -qO- ${FREETYPE_URL} | tar xfvz - && \
  cd ${FREETYPE}/builds && \
  PKG_CONFIG_PATH="$BUILD_PREFIX/lib/pkgconfig/" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$BUILD_PREFIX" -DCMAKE_BUILD_TYPE=Release -DENABLE_SHARED=OFF -DBUILD_SHARED_LIBS=OFF .. && \
  make && \
  make install

# libass
RUN wget -qO- ${ASS_URL} | tar xfvz - && \
  cd ${ASS} && \
  autoreconf -i && \
  PKG_CONFIG_PATH="$BUILD_PREFIX/lib/pkgconfig/" ./configure \
    --disable-shared \
    --enable-static \
    --disable-require-system-font-provider \
    --prefix=$BUILD_PREFIX && \
  make && \
  make install

# libaom
RUN git -C aom pull 2> /dev/null || git clone --depth 1 https://aomedia.googlesource.com/aom && \
  mkdir -p aom_build && \
  cd aom_build && \
  cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$BUILD_PREFIX" -DENABLE_TESTS=OFF -DENABLE_NASM=ON -DENABLE_SHARED=OFF -DBUILD_SHARED_LIBS=OFF ../aom && \
  make -j8 && \
  make install

# libx264
RUN wget -qO- ${X264_URL} | tar xfvz - && \
  cd x264-stable && \
  PKG_CONFIG_PATH="$BUILD_PREFIX/lib/pkgconfig/" ./configure \
    --disable-shared \
    --enable-static \
    --prefix=$BUILD_PREFIX && \
  make && \
  make install

# libx265
RUN wget -qO- ${X265_URL} | tar xfvz - && \
  cd ${X265}/build/linux && \
  PKG_CONFIG_PATH="$BUILD_PREFIX/lib/pkgconfig/" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$BUILD_PREFIX" -DENABLE_SHARED=off ../../source && \
  make && \
  make install && \
  sed -i 's/-lgcc_s/-lgcc_eh/g' $BUILD_PREFIX/lib/pkgconfig/x265.pc

# libfdk-aac
RUN wget -qO- ${FDKAAC_URL} | tar xfvz - && \
  cd ${FDKAAC} && \
  autoreconf -i && \
  PKG_CONFIG_PATH="$BUILD_PREFIX/lib/pkgconfig/" CFLAGS="-static" ./configure \
    --disable-shared \
    --enable-static \
    --prefix=$BUILD_PREFIX && \
  make -j8 && \
  make install

# liblame-mp3
RUN wget -qO- ${LAMEMP3_URL} | tar xfvz - && \
  cd ${LAMEMP3} && \
  PKG_CONFIG_PATH="$BUILD_PREFIX/lib/pkgconfig/" ./configure \
    --disable-shared \
    --enable-static \
    --prefix=$BUILD_PREFIX && \
  make -j8 && \
  make install

# libsvtav1
RUN git clone --depth 1 --branch v1.6.0 https://gitlab.com/AOMediaCodec/SVT-AV1.git && \
  cd SVT-AV1/Build && \
  cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$BUILD_PREFIX" -DCMAKE_BUILD_TYPE=Release -DBUILD_DEC=OFF -DENABLE_NASM=ON -DENABLE_SHARED=OFF -DBUILD_SHARED_LIBS=OFF .. && \
  make -j8 && \
  make install && \
  # libsvtav1 -> v1.6.0: patch for FFMpeg 5.1
  cp -r ../ffmpeg_plugin $BUILD_PREFIX/ffmpeg_plugin

WORKDIR /root

## Clone FFMpeg TAG n5.1
RUN git clone --depth 1 --branch n5.1 https://git.ffmpeg.org/ffmpeg.git ffmpeg && \
  git config --global user.email "media@loescher.it" && \
  git -C ffmpeg am $BUILD_PREFIX/ffmpeg_plugin/n5.1/*.patch
RUN cd ffmpeg && \
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
  --disable-ffplay \
  --disable-doc \
  --disable-podpages \
  --disable-debug \
  --disable-protocols \
  --disable-muxer=rtsp \
  --disable-encoder=rtsp \
  --disable-decoder=rtsp \
  && \
  make -j 10 && \
  make install
  ## install dest -> /root/bin/ --> ffmpeg + ffprobe
