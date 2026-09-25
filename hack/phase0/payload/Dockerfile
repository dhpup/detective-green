# Bases pinned by digest; must match GO_BUILD_IMAGE / DISTROLESS_STATIC_IMAGE in versions.env.
FROM golang:1.27@sha256:3680233e3204827fbdc66088528ae6d4b3d034f51d03a99d454f6de034888244 AS build
WORKDIR /src
COPY main.go .
RUN go mod init payload && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /payload .

FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab
COPY --from=build /payload /payload
USER 65532:65532
ENTRYPOINT ["/payload"]
