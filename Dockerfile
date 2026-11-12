# syntax=docker/dockerfile:1
# BYOND's Linux runtime is x86. Build/run this image on linux/amd64.
FROM ubuntu:24.04 AS toolchain
ARG TARGETARCH
ARG UBUNTU_MIRROR
ENV DEBIAN_FRONTEND=noninteractive
RUN test "$TARGETARCH" = amd64 \
 && dpkg --add-architecture i386 \
 && if [ -n "$UBUNTU_MIRROR" ]; then sed -i -E "s@http://(archive|security).ubuntu.com/ubuntu/?@${UBUNTU_MIRROR%/}@g" /etc/apt/sources.list.d/ubuntu.sources; fi \
 && apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o APT::Update::Error-Mode=any update \
 && apt-get install -y --no-install-recommends \
    ca-certificates curl unzip make python3 python3-pip nodejs \
    libc6:i386 libstdc++6:i386 libgcc-s1:i386 zlib1g:i386 \
    libssl3t64:i386 libcurl4t64:i386 \
 && rm -rf /var/lib/apt/lists/*
COPY dependencies.sh /tmp/dependencies.sh
COPY container/install-toolchain.sh /tmp/install-toolchain.sh
RUN bash /tmp/install-toolchain.sh
ENV PATH="/opt/byond/bin:${PATH}" LD_LIBRARY_PATH=/opt/byond/bin

FROM toolchain AS build
WORKDIR /src
# The supervisor's Discord bot (discord.py); copied into the runtime image.
COPY services/supervisor/requirements.txt /tmp/requirements.txt
RUN python3 -m pip install --no-cache-dir --break-system-packages --target /opt/pydeps -r /tmp/requirements.txt
ENV PYTHONPATH=/opt/pydeps
COPY . .
RUN bun install --frozen-lockfile --ignore-scripts \
 && cd tgui && bun install --frozen-lockfile --ignore-scripts \
 && cd packages/tgfont && bun run tgfont:build \
 && cd /src/tgui && bun run tgui:build
RUN . ./dependencies.sh \
 && curl -fSL --retry 3 "https://github.com/${CUTTER_REPO}/releases/download/${CUTTER_VERSION}/hypnagogic" -o /tmp/hypnagogic \
 && chmod +x /tmp/hypnagogic \
 && /tmp/hypnagogic --dont-wait --templates cutter_templates icons \
 && /tmp/hypnagogic --dont-wait --templates cutter_templates modular_zubbers/icons \
 && python3 tools/build_bt.py
RUN DreamMaker -DCBT babylon.dme && DreamMaker -DCBT babylon-lobby.dme
RUN python3 container/stage-runtime.py /src /opt/babylon

# PRs and default-branch pushes build this target: both game builds, the
# standalone lobby, upstream compatibility, Python tests and browser UX tests.
FROM build AS check
RUN DreamMaker -DCBT babylon-test.dme && DreamMaker -DCBT tgstation.dme \
 && python3 -m unittest discover -s services/supervisor -v \
 && node tools/babylon/test_lobby_loading.cjs \
 && node container/test_cleanup.cjs

FROM ubuntu:24.04 AS runtime
ARG UBUNTU_MIRROR
ENV DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture i386 \
 && if [ -n "$UBUNTU_MIRROR" ]; then sed -i -E "s@http://(archive|security).ubuntu.com/ubuntu/?@${UBUNTU_MIRROR%/}@g" /etc/apt/sources.list.d/ubuntu.sources; fi \
 && apt-get -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o APT::Update::Error-Mode=any update \
 && apt-get install -y --no-install-recommends \
    ca-certificates python3 libc6:i386 libstdc++6:i386 libgcc-s1:i386 \
    zlib1g:i386 libssl3t64:i386 libcurl4t64:i386 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --uid 10001 --create-home babylon \
 && mkdir -p /data /run/babylon && chown babylon:babylon /data /run/babylon
COPY --from=toolchain /opt/byond /opt/byond
COPY --from=toolchain /opt/native /opt/native
COPY --from=build /opt/babylon /opt/babylon
COPY --from=build /opt/pydeps /opt/pydeps
ENV PATH="/opt/byond/bin:${PATH}" LD_LIBRARY_PATH=/opt/byond/bin \
    HOME=/home/babylon PYTHONUNBUFFERED=1 PYTHONPATH=/opt/pydeps
USER babylon
WORKDIR /opt/babylon
VOLUME ["/data"]
EXPOSE 1361/tcp 1400-1420/tcp
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD ["python3", "/opt/babylon/container/entrypoint.py", "--healthcheck"]
ENTRYPOINT ["python3", "/opt/babylon/container/entrypoint.py"]
