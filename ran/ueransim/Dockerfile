FROM ubuntu:jammy

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        apt-transport-https \
        ca-certificates \
        cmake \
        g++ \
        git \
        iproute2 \
        iputils-ping \
        libsctp-dev \
        lksctp-tools \
        make \
        net-tools \
        pkg-config \
        wget \
    && rm -rf /var/lib/apt/lists/*

COPY sources/UERANSIM /UERANSIM
WORKDIR /UERANSIM
RUN make -j"$(nproc)"

CMD ["/mnt/ueransim/ueransim_init.sh"]
