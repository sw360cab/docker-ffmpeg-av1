FROM node:18-bullseye

WORKDIR /usr/src/app
# src files
COPY . .

# ffmpeg
COPY --from=ffmpeg-exec /root/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --from=ffmpeg-exec /root/bin/ffprobe /usr/local/bin/ffprobe

# node user configuration
ARG UID=1000
ENV UID=${UID}
ARG GID=1000
ENV GID=${GID}

# node modules
RUN npm install --omit=dev
RUN groupmod -g ${GID} node && usermod -u ${UID} -g ${GID} node \ 
  && chown -R node:node .
USER node

ENTRYPOINT [ "node", "index.js" ]
