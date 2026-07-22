#!/bin/bash
# Builds a release and zips it for a GitHub Release.
#   Scripts/release.sh 1.0.0  ->  build/PIcturizeTeX-1.0.0.zip
set -euo pipefail

VERSION="${1:?usage: release.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

VERSION="$VERSION" "$ROOT/Scripts/bundle.sh" release

ZIP="$ROOT/build/PIcturizeTeX-$VERSION.zip"
rm -f "$ZIP"
# ditto preserves the bundle structure, resource forks, and the signature.
ditto -c -k --keepParent "$ROOT/build/PIcturizeTeX.app" "$ZIP"
echo "$ZIP"
