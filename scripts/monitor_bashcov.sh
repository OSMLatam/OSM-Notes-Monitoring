#!/usr/bin/env bash
# Monitor bashcov progress (alias for run_bashcov_background.sh monitor)
exec bash "$(dirname "$0")/run_bashcov_background.sh" monitor "$@"
