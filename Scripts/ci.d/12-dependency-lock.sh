#!/usr/bin/env bash
# Dependency lock and license inventory (plan 21.2, 22.2; ADR-0014). Checks every committed Package.resolved,
# Package.swift and project.yml, the license text copies, the vendored fonts and license files under Apps/ and
# Packages/, the Python tool pins and the workflow actions against Docs/Licenses/inventory.json, then the installed
# Xcode build, Swift and XcodeGen versions and the tools virtualenv against their pins. The checker's self-test runs
# first, so a check that could no longer detect a failure it claims fails this step.
#
# Fails when a pin differs from the inventory, a package is not in the inventory, a requirement is not an exact
# version, an Xcode project or workspace is committed, a spike-only package (or any code under Spikes/ or elsewhere
# outside Apps/ and Packages/, package checkouts and build products included) can reach a product target, a product
# target passes a flag outside the allowed list or replaces a build tool, product code reaches a transitive-only
# package's modules or headers (by import, include, module map, module alias, -import-module, -include, a prefix or
# bridging header, a definition or any manifest value), or a third-party binary is not inventoried. Since ADR-0014's
# review round 4 (R4-01 to R4-04), also when a product manifest's values depend on what the check does not read
# (XcodeGen's ${NAME} and leading ~ in a product project.yml; a product Package.swift that reads anything but its own
# text), product code brings in a file by an include whose path is absolute, climbs out with .., passes through a
# build or checkout directory or is computed, a build-settings file #includes one that is not tracked under the
# product roots, or a product manifest redefines a variable the check evaluates itself; the full list is in
# Scripts/check-dependency-lock.py. It warns, without failing, when the tools virtualenv's pip (which nothing pins,
# so a fresh virtualenv holds the one its Python bundles) is below the minimum the inventory records (ADR-0014 section
# 3). Scripts/ci.sh prints a drop-in's log only when it fails, so in a passing run that warning appears only in
# .build/ci-logs/12-dependency-lock.log, where the check prints its warnings last, just before its summary line.
# The self-test fails unless every failure branch of the check is reached by a mutation written for it, and every
# warning branch by an allowed change written for it. Host only: no network, no simulator, no build.
set -euo pipefail
source "$(cd "$(dirname "$0")/../lib" && pwd)/env.sh"
cd "$SYLVIA_ROOT"

echo "12-dependency-lock $(date -u +%Y-%m-%dT%H:%M:%SZ) at commit $(git rev-parse HEAD)"
echo "host: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)); $(xcodebuild -version | tr '\n' ' ')"
echo "load: $(uptime)"

echo
echo "--- self-test: synthetic trees, one per failure the check claims to detect"
sylvia_python Scripts/check-dependency-lock.py self-test

echo
echo "--- check: this repository against Docs/Licenses/inventory.json, and the installed toolchain"
sylvia_python Scripts/check-dependency-lock.py check --toolchain
