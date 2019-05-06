#! /usr/bin/env bash
set -euo pipefail

manifests=$(nix-build --no-link -QA k8s.simulation-tests.foundationdb61)
tests=$(cd "$manifests" && find . -type f -iname 'simulation-*.yaml')

for x in $tests; do
  m=$(basename "$x" .yaml)
  echo "executing jobs.batch/$m..."

  set -x
  kubectl apply -f "$manifests/$m.yaml"
  kubectl wait --for=condition=complete --timeout=1h "job/$m"
  kubectl delete -f "$manifests/$m.yaml"
  set +x
done
