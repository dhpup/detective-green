#!/usr/bin/env python3
"""Minimal anonymous OCI registry client (stdlib only).

  oci.py digest <image:tag>                     print the manifest (index) digest
  oci.py pull-chart <repo> <version> <digest> <out.tgz>
                                                download a Helm chart stored as an
                                                OCI artifact and verify its layer digest

Used instead of `helm pull oci://` and registry CLIs so the only dependency
for `make up` is python3, and so charts are verified against a pinned digest.
"""
import hashlib
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

ACCEPT = ", ".join([
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.v2+json",
])
HELM_LAYER = "application/vnd.cncf.helm.chart.content.v1.tar+gzip"


def split_ref(ref):
    name, _, tag = ref.rpartition(":")
    if "/" in tag or not name:
        name, tag = ref, "latest"
    registry, _, repo = name.partition("/")
    if "." not in registry and ":" not in registry and registry != "localhost":
        registry, repo = "registry-1.docker.io", name
    if registry in ("docker.io", "index.docker.io"):
        registry = "registry-1.docker.io"
    if registry == "registry-1.docker.io" and "/" not in repo:
        repo = "library/" + repo
    return registry, repo, tag


def request(url, headers, method="GET", token=None):
    if token:
        headers = dict(headers, Authorization="Bearer " + token)
    req = urllib.request.Request(url, headers=headers, method=method)
    return urllib.request.urlopen(req, timeout=60)


def token_for(challenge, repo):
    params = dict(re.findall(r'(\w+)="([^"]*)"', challenge))
    query = {"service": params.get("service", ""), "scope": f"repository:{repo}:pull"}
    url = params["realm"] + "?" + urllib.parse.urlencode(query)
    with urllib.request.urlopen(url, timeout=60) as resp:
        body = json.load(resp)
    return body.get("token") or body.get("access_token")


def fetch(registry, repo, path, headers, method="GET"):
    url = f"https://{registry}/v2/{repo}/{path}"
    try:
        return request(url, headers, method)
    except urllib.error.HTTPError as err:
        if err.code != 401:
            raise
        return request(url, headers, method, token_for(err.headers["WWW-Authenticate"], repo))


def digest(ref):
    registry, repo, tag = split_ref(ref)
    try:
        with fetch(registry, repo, f"manifests/{tag}", {"Accept": ACCEPT}, method="HEAD") as resp:
            return resp.headers["Docker-Content-Digest"]
    except urllib.error.HTTPError as err:
        if err.code != 405:  # some registries (registry.k8s.io) don't allow HEAD
            raise
    with fetch(registry, repo, f"manifests/{tag}", {"Accept": ACCEPT}) as resp:
        body = resp.read()
        return resp.headers.get("Docker-Content-Digest") or "sha256:" + hashlib.sha256(body).hexdigest()


def pull_chart(repo_ref, version, want, out):
    registry, repo, _ = split_ref(repo_ref + ":" + version)
    with fetch(registry, repo, f"manifests/{version}", {"Accept": ACCEPT}) as resp:
        manifest = json.load(resp)
    layer = next(l for l in manifest["layers"] if l["mediaType"] == HELM_LAYER)
    if layer["digest"] != want:
        sys.exit(f"chart digest mismatch for {repo_ref}:{version}: got {layer['digest']}, pinned {want}")
    with fetch(registry, repo, f"blobs/{layer['digest']}", {}) as resp:
        data = resp.read()
    got = "sha256:" + hashlib.sha256(data).hexdigest()
    if got != want:
        sys.exit(f"downloaded chart does not match pinned digest: {got} != {want}")
    with open(out, "wb") as f:
        f.write(data)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "digest":
        print(digest(sys.argv[2]))
    elif len(sys.argv) == 6 and sys.argv[1] == "pull-chart":
        pull_chart(*sys.argv[2:])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
