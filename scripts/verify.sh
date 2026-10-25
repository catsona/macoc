#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
bash "$ROOT/scripts/lint.sh"
bash "$ROOT/scripts/test.sh"
