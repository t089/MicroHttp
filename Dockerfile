FROM ubuntu:18.04

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true && apt-get -q update && \
    apt-get -q install -y \
    libatomic1 \
    libbsd0 \
    libcurl4 \
    libxml2 \
    libedit2 \
    libsqlite3-0 \
    libc6-dev \
    binutils \
    libgcc-5-dev \
    libstdc++-5-dev \
    libpython2.7 \
    tzdata \
    git \
    curl \
    pkg-config



RUN curl -s https://packagecloud.io/install/repositories/swift-arm/release/script.deb.sh |  bash

RUN apt-get -q install -y swift5=5.1.3-v0.1

RUN rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Package.swift ./
COPY Sources ./Sources
COPY Tests ./Tests

RUN swift test
#CMD [ ".build/debug/MicroHttpExample"]