#!/usr/bin/env bash
export DEBUG_MODE="${DEBUG_MODE:-false}"
export TRACE_MODE="${TRACE_MODE:-false}"

_fail() {
  >&2 echo "ERROR: $1"
  exit 1
}

_log_error() {
  >&2 echo "ERROR: $1"
}

_log_warning() {
  >&2 echo "WARN: $1"
}

_log_trace() {
  if grep -Eiq '^true$' <<< "$TRACE_MODE"
  then
    >&2 echo "TRACE: $1"
  fi
}

_log_debug() {
  if grep -Eiq "^true$" <<< "$DEBUG_MODE" || grep -Eiq '^true$' <<< "$TRACE_MODE"
  then
    >&2 echo "DEBUG: $1"
  fi
}

_log_info() {
  >&2 echo "INFO: $1"
}
