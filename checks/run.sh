#!/bin/sh
# Compiles the rule logic and file marks with checks/main.swift and runs them.
set -e
cd "$(dirname "$0")/.."
out=.build/checks
mkdir -p .build
swiftc -swift-version 6 -o "$out" checks/main.swift \
  congruitas/Models/Rule.swift congruitas/Services/FileMarks.swift congruitas/Services/Placement.swift
"$out"
