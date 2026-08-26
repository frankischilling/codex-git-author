#!/usr/bin/env bash
set -euo pipefail

TEST_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec bash "$TEST_DIRECTORY/git-commit-author-test.sh" "$@"
