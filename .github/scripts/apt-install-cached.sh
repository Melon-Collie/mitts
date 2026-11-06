#!/bin/bash
# Installs apt packages from a directory actions/cache carries between runs,
# reaching the mirror only when that directory can't satisfy the install.
#
#   apt-install-cached.sh <cache-dir> [apt-get install args...] <package>...
#
# <cache-dir>/lists is a snapshot of the package lists and <cache-dir>/debs the
# .debs fetched against it. The two are only valid as a pair, which is why the
# lists are cached instead of read from the runner image: the image's own lists
# may be absent, or newer than the cached .debs.
#
# The first attempt never touches the network. When it misses (a cold cache, a
# package added, a snapshot that no longer fits the image), the lists are
# refreshed once per job and the missing .debs are fetched into the cache, and
# `refreshed=true` goes to $GITHUB_OUTPUT so the workflow saves the new snapshot.
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <cache-dir> [apt-get install args...] <package>..." >&2
  exit 2
fi

cache="$1"
shift
lists="$cache/lists"
debs="$cache/debs"
# Per job, not per cache: a second call in the same job reuses the first
# call's refresh instead of fetching the lists again.
refreshed_marker="${RUNNER_TEMP:-/tmp}/apt-lists-refreshed"

apt_opts=(
  -o "Dir::State::Lists=$lists"
  -o "Dir::Cache::Archives=$debs"
  -o Acquire::Retries=3
  -o Acquire::http::Timeout=30
  -o Acquire::https::Timeout=30
  # The cache lives under the runner's home, which the _apt download user
  # can't write to; without this apt warns and downloads as root anyway.
  -o APT::Sandbox::User=root
)

# apt leaves lock files and root-only partial/ dirs behind, which the cache
# save (running as the runner user) can't read. Hand the tree back either way.
finish() {
  sudo rm -rf "$lists/partial" "$debs/partial" "$lists/lock" "$debs/lock"
  sudo chown -R "$(id -u):$(id -g)" "$cache"
}
trap finish EXIT

sudo mkdir -p "$lists/partial" "$debs/partial"

echo "[apt-cache] installing from the cache, offline: $*"
if sudo apt-get install -y -qq --no-download "${apt_opts[@]}" "$@"; then
  echo "[apt-cache] installed from the cache"
  exit 0
fi

echo "[apt-cache] the cache can't satisfy this install; fetching from the mirror"
if [ ! -e "$refreshed_marker" ]; then
  sudo apt-get update -qq "${apt_opts[@]}"
  touch "$refreshed_marker"
fi
sudo apt-get install -y -qq "${apt_opts[@]}" "$@"
# Drops .debs the refreshed lists no longer offer, so the cache doesn't keep
# every superseded version it ever fetched.
sudo apt-get autoclean -qq "${apt_opts[@]}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "refreshed=true" >> "$GITHUB_OUTPUT"
fi
