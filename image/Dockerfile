# KCD:MP dedicated server for Pterodactyl.
#
# KcdMp.Server.runtimeconfig.json (server 0.50.0) lists one framework,
# Microsoft.NETCore.App 10.0.0, and System.Globalization.Invariant is true, so
# the plain runtime image is enough - no ASP.NET Core, no ICU.
#
# A glibc base is mandatory: the server ships liblua54.so, libenet.so and
# libe_sqlite3.so as glibc ELF objects with no musl builds. The runtime image is
# Ubuntu-based, which satisfies that.
FROM --platform=$TARGETOS/$TARGETARCH mcr.microsoft.com/dotnet/runtime:10.0

LABEL org.opencontainers.image.title="kcdmp"
LABEL org.opencontainers.image.description="KCD:MP dedicated server runtime image for Pterodactyl"
LABEL org.opencontainers.image.source="https://github.com/ewbree/pterodactyl-kcd-multiplayer"
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive

# tini reaps zombies and forwards signals, passwd provides useradd for the
# non-root user Wings expects. curl and unzip fetch and unpack the server
# release, jq reads the GitHub release metadata (parsing JSON with sed is the
# kind of thing that breaks silently).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates tzdata iproute2 tini passwd curl unzip jq \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -d /home/container container \
 && chown container:container /home/container

USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

COPY --chmod=755 ./entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=755 ./render-server-toml.sh /usr/local/bin/render-server-toml.sh
COPY --chmod=755 ./update-server.sh /usr/local/bin/update-server.sh

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/usr/local/bin/entrypoint.sh"]
