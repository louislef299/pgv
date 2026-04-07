# syntax=docker/dockerfile:1.7
# check=error=true
FROM alpine:3.23.3

RUN apk -U upgrade && \
    apk add --no-cache build-base zig libgit2

CMD ["zsh"]
