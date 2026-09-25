# case-file: one static binary on distroless, running as non-root.
# Bases are pinned by digest and must match GO_BUILD_IMAGE and
# DISTROLESS_STATIC_IMAGE in versions.env (checked by hack/verify-pins.sh).
ARG GO_IMAGE=golang:1.27@sha256:3680233e3204827fbdc66088528ae6d4b3d034f51d03a99d454f6de034888244
ARG BASE_IMAGE=gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS build
ARG TARGETOS TARGETARCH
ARG VERSION=dev
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download && go mod verify
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /case-file .

FROM ${BASE_IMAGE}
COPY --from=build /case-file /case-file
# node-tuner overrides this with runAsUser: 0 (it needs NET_ADMIN, nothing else).
USER 65532:65532
ENTRYPOINT ["/case-file"]
