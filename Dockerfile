# syntax=docker/dockerfile:1.7
# check=error=true
FROM alpine:edge

RUN apk add --no-cache build-base \
    zig libgit2

WORKDIR /app
COPY . .
RUN zig build

CMD ["/app/zig-out/bin/rmt"]
