#!/bin/bash
exec "$(cd "$(dirname "$0")/../../scripts" && pwd)/$(basename "$0")" "$@"
