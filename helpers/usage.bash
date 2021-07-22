#!/usr/bin/env bash
usage() {
  if test -z "$USAGE_TEXT"
  then
    >&2 echo "ERROR: USAGE_TEXT is not defined. \
Help a fellow developer and define it :)"
    exit 1
  fi
  echo "$USAGE_TEXT"
}

show_usage_if_requested() {
  if [ "$1" == "-h" ] || [ "$1" == "--help" ]
  then
    usage
    exit 0
  fi
}
