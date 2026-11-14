# Build on a machine that can reach the mirror, then load the image.
# The guest must not pull this during android-ue-up.
# The Docker host that runs the emulator has no egress either. Do not build
# or pull this image there. docker save, then load, and pin name@sha256.
FROM node:22-bookworm-slim@sha256:5ec23b7c622b00547753bc6ffd78085dd868a68aeb41c8e0a1418f033e13d96d

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl python3 make g++ adb patch \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/ws-scrcpy
ARG WS_SCRCPY_COMMIT=ef273d97c6ac0c05d03b41d4b55d59a25b95c505
ARG WS_SCRCPY_TARBALL_SHA256=bd8140c07de422b29eeddb28e1b4c54f1652c554805837f2b25dd0c26d7c2aac
RUN curl -fsSL -o /tmp/ws-scrcpy.tar.gz \
      "https://github.com/NetrisTV/ws-scrcpy/archive/${WS_SCRCPY_COMMIT}.tar.gz" \
    && echo "${WS_SCRCPY_TARBALL_SHA256}  /tmp/ws-scrcpy.tar.gz" | sha256sum -c \
    && tar -xzf /tmp/ws-scrcpy.tar.gz -C /opt/ws-scrcpy --strip-components=1 \
    && rm /tmp/ws-scrcpy.tar.gz

COPY build.config.override.json /opt/ws-scrcpy/build.config.override.json
COPY patches/ /tmp/open5g-patches/
RUN patch -p1 < /tmp/open5g-patches/0001-pathname.patch \
    && patch -p1 < /tmp/open5g-patches/0002-open5g-bind.patch \
    && rm -rf /tmp/open5g-patches
RUN npm ci && npm run dist

EXPOSE 8000
CMD ["npm", "start"]
