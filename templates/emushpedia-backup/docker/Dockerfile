FROM alpine:3.22

# UID/GID of the container user: must own live/<env>/secrets and live/<env>/data
# on the host (ssh refuses a private key it does not own).
ARG UID=1000
ARG GID=1000

RUN apk add --no-cache bash flock openssh-client restic rsync supercronic tzdata \
 && addgroup -g "$GID" backup \
 && adduser -D -u "$UID" -G backup -h /home/backup backup

COPY --chmod=755 backup.sh /usr/local/bin/backup
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint

# Lets `docker exec <container> restic ...` work without any extra setup.
ENV RESTIC_REPOSITORY=/data/restic \
    RESTIC_PASSWORD_FILE=/config/restic.pwd \
    RESTIC_CACHE_DIR=/data/cache

USER backup
WORKDIR /home/backup
ENTRYPOINT ["/usr/local/bin/entrypoint"]
