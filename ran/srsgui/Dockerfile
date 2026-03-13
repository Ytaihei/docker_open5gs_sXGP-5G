FROM ubuntu:20.04
LABEL maintainer="srsGUI Team"

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    libboost-system-dev \
    libboost-test-dev \
    libboost-thread-dev \
    libqwt-qt5-dev \
    qtbase5-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY sources/srsGUI /srsGUI

# Build srsGUI
WORKDIR /srsGUI
RUN rm -rf build && mkdir build && cd build && \
    cmake ../ && \
    make -j$(nproc) && \
    make install

WORKDIR /
CMD ["sleep", "infinity"]
