#!/usr/bin/env python3
"""Fail if any relative markdown link in the repo points to a file that doesn't exist."""
import glob, os, re, sys
bad = []
for f in glob.glob("**/*.md", recursive=True):
    if "/charts/" in f: continue   # vendored Helm charts (kustomize cache), not ours
    for link in re.findall(r"\]\(([^)#]+?)(?:#[^)]*)?\)", open(f).read()):
        if link.startswith(("http://", "https://", "mailto:")): continue
        if not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(f), link))): bad.append(f"{f}: {link}")
print(f"checked markdown links; broken: {len(bad)}")
for b in bad: print("  BROKEN", b)
sys.exit(1 if bad else 0)
