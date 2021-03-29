ARG MOSQUITTO_VERSION=1.6.10

#Use debian:stable-slim as a builder and then copy everything.
FROM debian:stable-slim as builder1
ARG MOSQUITTO_VERSION

WORKDIR /app
#Get mosquitto build dependencies.
RUN apt update && apt install -y libwebsockets-dev libssl-dev wget build-essential
RUN mkdir -p mosquitto/auth mosquitto/conf.d

RUN wget http://mosquitto.org/files/source/mosquitto-${MOSQUITTO_VERSION}.tar.gz
RUN tar xzvf mosquitto-${MOSQUITTO_VERSION}.tar.gz

#Build mosquitto.
RUN cd mosquitto-${MOSQUITTO_VERSION} && make WITH_WEBSOCKETS=yes && make install


FROM --platform=$BUILDPLATFORM golang:latest AS builder2

ENV CGO_CFLAGS="-I/usr/local/include -fPIC"
ENV CGO_LDFLAGS="-shared -Wl,-unresolved-symbols=ignore-all"
ENV CGO_ENABLED=1

RUN apt update && apt install -y gcc-arm-linux-gnueabihf libc6-dev-armhf-cross gcc-aarch64-linux-gnu libc6-dev-arm64-cross

# Install TARGETPLATFORM parser to translate its value to GOOS, GOARCH, and GOARM
COPY --from=tonistiigi/xx:golang / /
# Bring TARGETPLATFORM to the build scope
ARG TARGETPLATFORM
RUN go env

WORKDIR /app
COPY --from=builder1 /usr/local/include/ /usr/local/include/

COPY ./ ./
RUN go build -buildmode=c-archive go-auth.go && \
    go build -buildmode=c-shared -o go-auth.so && \
	go build pw-gen/pw.go


#Start from a new image.
FROM debian:stable-slim

RUN apt update && apt install -y libwebsockets8 libc-ares2 openssl uuid

RUN mkdir -p /var/lib/mosquitto /var/log/mosquitto 
RUN groupadd mosquitto \
    && useradd -s /sbin/nologin mosquitto -g mosquitto -d /var/lib/mosquitto \
    && chown -R mosquitto:mosquitto /var/log/mosquitto/ \
    && chown -R mosquitto:mosquitto /var/lib/mosquitto/

#Copy confs, plugin so and mosquitto binary.
COPY --from=builder1 /app/mosquitto/ /mosquitto/
COPY --from=builder2 /app/pw /mosquitto/pw
COPY --from=builder2 /app/go-auth.so /mosquitto/go-auth.so
COPY --from=builder1 /usr/local/sbin/mosquitto /usr/sbin/mosquitto

EXPOSE 1883 1884

ENTRYPOINT ["sh", "-c", "/usr/sbin/mosquitto -c /etc/mosquitto/mosquitto.conf" ]