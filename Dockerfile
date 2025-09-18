FROM golang:alpine AS builder

ARG CGO_ENABLED=1

RUN echo "**** Install Dependencies ****" && \
    apk add --no-cache \
        make \
        bash \
        gawk \
        git \
        curl \
        build-base \
        binutils-gold

RUN echo "**** [Rclone] Download Source Code ****" && \
    curl -s https://api.github.com/repos/tgdrive/rclone/releases/latest | \
    grep "tarball_url" | \
    cut -d '"' -f 4 | \
    xargs -n1 curl -Ls --output rclone.tar.gz && \
    mkdir -p /go/src/github.com/rclone/rclone/ && \
    tar -xvzf rclone.tar.gz -C /go/src/github.com/rclone/rclone/ --strip-components=1 && \
    rm rclone.tar.gz

WORKDIR /go/src/github.com/rclone/rclone/

RUN echo "**** Set Go Environment Variables ****" && \
    go env -w GOCACHE=/root/.cache/go-build

RUN echo "**** [Rclone] Download Go Dependencies ****" && \
    go mod download -x

RUN echo "**** [Rclone] Verify Go Dependencies ****" && \
    go mod verify

RUN --mount=type=cache,target=/root/.cache/go-build,sharing=locked \
    echo "**** [Rclone] Build Binary ****" && \
    make

RUN echo "**** [Rclone] Print Version Binary ****" && \
    ./rclone version

RUN echo "**** [TeleBox] Download Source Code ****" && \
    curl -Ls --output rclone-telebox-plugin.tar.gz https://github.com/ky1vstar/rclone-telebox-plugin/archive/refs/heads/main.tar.gz && \
    mkdir -p /go/src/github.com/ky1vstar/rclone-telebox-plugin/ && \
    tar -xvzf rclone-telebox-plugin.tar.gz -C /go/src/github.com/ky1vstar/rclone-telebox-plugin/ --strip-components=1 && \
    rm rclone-telebox-plugin.tar.gz

WORKDIR /go/src/github.com/ky1vstar/rclone-telebox-plugin/

RUN echo "**** [TeleBox] Download Go Dependencies ****" && \
    go mod edit -replace "github.com/rclone/rclone=/go/src/github.com/rclone/rclone" && \
    go mod tidy && \
    go mod download -x

RUN echo "**** [TeleBox] Verify Go Dependencies ****" && \
    go mod verify

RUN --mount=type=cache,target=/root/.cache/go-build,sharing=locked \
    echo "**** [TeleBox] Build Binary ****" && \
    go build -buildmode=plugin -o librcloneplugin_telebox.so

ENV RCLONE_PLUGIN_PATH=/go/src/github.com/ky1vstar/rclone-telebox-plugin/

RUN echo "**** [TeleBox] Print Backend Help ****" && \
    /go/src/github.com/rclone/rclone/rclone help backend telebox

# Begin final image
FROM alpine:latest

RUN echo "**** Install Dependencies ****" && \
    apk add --no-cache \
        ca-certificates \
        fuse3 \
        tzdata && \
    echo "Enable user_allow_other in fuse" && \
    echo "user_allow_other" >> /etc/fuse.conf

COPY --from=builder /go/src/github.com/rclone/rclone/rclone /usr/local/bin/

COPY --from=builder /go/src/github.com/ky1vstar/rclone-telebox-plugin/librcloneplugin_telebox.so /etc/rclone/plugins/librcloneplugin_telebox.so

RUN addgroup -g 1009 rclone && adduser -u 1009 -Ds /bin/sh -G rclone rclone

ENTRYPOINT [ "rclone" ]

WORKDIR /data
ENV XDG_CONFIG_HOME=/config
ENV RCLONE_PLUGIN_PATH=/etc/rclone/plugins