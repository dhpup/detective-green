# evidence-kit: minimal capture image (tcpdump + iproute2 + ethtool).
# Used for Chapter 4 captures and by hack/prepare-nodes.sh to set NIC offloads.
# The base is pinned by digest in versions.env (ALPINE_IMAGE) and passed in by
# the build; the default below must match it.
ARG BASE_IMAGE=alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8
FROM ${BASE_IMAGE}
RUN apk add --no-cache tcpdump iproute2 ethtool
ENTRYPOINT ["tcpdump"]
