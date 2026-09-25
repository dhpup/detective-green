#!/usr/bin/env bash
# Chapter 2, the warm-up case: flow logs solve it in seconds.
# Shows Hubble's DROPPED flows in prod's cold-case namespace: the client (v1.3)
# calls fingerprints on port 9090, and the policy only allows 8080.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

prod="$(ctx prod)"
node="$(kubectl --context "$prod" -n cold-case get pod -l app=fingerprints -o jsonpath='{.items[0].spec.nodeName}')"
[[ -n "$node" ]] || die "cold-case isn't running in prod (is apps/cold-case synced?)"
agent="$(kubectl --context "$prod" -n kube-system get pod -l k8s-app=cilium --field-selector "spec.nodeName=${node}" -o name)"

say "$ hubble observe --namespace cold-case --verdict DROPPED"
kubectl --context "$prod" -n kube-system exec "$agent" -c cilium-agent -- \
  hubble observe --namespace cold-case --verdict DROPPED --last "${LAST:-8}" -o compact
