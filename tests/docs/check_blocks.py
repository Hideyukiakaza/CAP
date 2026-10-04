#!/usr/bin/env python3
"""Fail if any ```cap block in the docs does not match a file in docs/examples/."""
import glob, os, re, sys

root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ex_files = set()
for p in glob.glob(os.path.join(root, "docs", "examples", "*.cap")):
    with open(p) as f:
        text = f.read()
        if text.endswith("\n"):
            text = text[:-1]
        ex_files.add(text)

failed = False
for doc in ["README.md", "docs/LANGUAGE.md", "docs/GUIDE.md"]:
    path = os.path.join(root, doc)
    if not os.path.exists(path):
        continue
    with open(path) as f:
        content = f.read()
    for i, block in enumerate(re.findall(r"```cap\n(.*?)```", content, re.DOTALL), 1):
        b = block
        if b.endswith("\n"):
            b = b[:-1]
        if b not in ex_files:
            print(f"FAIL doc check {doc} block {i}:\n{b}\n")
            failed = True

if failed:
    sys.exit(1)
print("PASS     docs_code_block_match")
