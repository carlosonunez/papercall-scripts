#!/usr/bin/env bash

_next_arg_is_arg() {
  grep -Eiq -- '^--' <<< "$1"
}

_verify_required_arg_or_fail() {
  key="$1"
  val="$2"
  if test -z "$val"
  then
    usage
    echo
    _fail "$key is required"
  fi
}

