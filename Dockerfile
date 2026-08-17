# Add a small HTTP listener around the official OtoHits client image.
#
# Render Web Services must bind to $PORT. The official client is still the
# foreground process; the listener only exposes deployment/health status.
FROM golang:1.24-alpine AS health-build
WORKDIR /src
COPY healthcheck.go .
RUN CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /out/otohit-health healthcheck.go

FROM otohits/app:latest
COPY --from=health-build /out/otohit-health /usr/local/bin/otohit-health
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint-web
RUN chmod 755 /usr/local/bin/docker-entrypoint-web

# The wrapper starts the HTTP listener and the Xvfb display required by the
# Chromium-based OtoHits viewer, then supervises the client. It replaces the
# upstream ENTRYPOINT, so it also reproduces the upstream launcher's essential
# /nosandbox setting and locates the client when the upstream CMD is empty.
ENTRYPOINT ["/usr/local/bin/docker-entrypoint-web"]
