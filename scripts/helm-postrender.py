#!/usr/bin/env python3
"""Helm post-renderer: patch rendered manifests with things the chart can't express.
Reads the full rendered YAML on stdin, writes the patched YAML on stdout (Helm's post-renderer contract).
Config: apps/astronomy-shop/postrender.yaml
  deployments.<name>.strategy                     -> spec.strategy
  deployments.<name>.containers.<container>.<k>   -> merged into that container (e.g. readinessProbe/livenessProbe)
Fails loudly if a configured deployment/container doesn't exist, so a chart upgrade can't silently drop a patch."""
import os, sys, yaml
cfg_path = os.path.join(os.path.dirname(__file__), "..", "apps", "astronomy-shop", "postrender.yaml")
cfg = (yaml.safe_load(open(cfg_path)) or {}).get("deployments", {})
docs = list(yaml.safe_load_all(sys.stdin))
seen = set()
for d in docs:
    if not d or d.get("kind") != "Deployment": continue
    name = d["metadata"]["name"]
    if name not in cfg: continue
    seen.add(name); spec = cfg[name]
    if "strategy" in spec: d["spec"]["strategy"] = spec["strategy"]
    containers = {c["name"]: c for c in d["spec"]["template"]["spec"]["containers"]}
    for cname, patch in (spec.get("containers") or {}).items():
        if cname not in containers: sys.exit(f"postrender: container {cname!r} not found in deployment {name!r}")
        containers[cname].update(patch)
missing = set(cfg) - seen
if missing: sys.exit(f"postrender: deployments not found in rendered chart: {sorted(missing)}")
yaml.safe_dump_all([d for d in docs if d is not None], sys.stdout, sort_keys=False)
