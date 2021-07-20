#!/usr/bin/env bash
# vi: set ft=bash:
PAPERCALL_SESSION_COOKIE_FILE="${PAPERCALL_SESSION_COOKIE_FILE:-$PWD/.papercall_cookie}"
DEBUG_MODE="${DEBUG_MODE:-false}"

usage() {
  cat <<-USAGE
PAPERCALL_SESSION_COOKIE_FILE=\$file $(basename $0) [options]
Changes the state of one or more Papercall talks

ENVIRONMENT VARIABLES

  PAPERCALL_SESSION_COOKIE_FILE       The file containing your Papercall cookie.
                                      See "NOTES" for info on how to retrieve it.
                                      Defaults to $PWD/.papercall_cookie.

OPTIONS

  --event-name [NAME]                 The name of the event in which the talks are located.
  --talks [TALK_1,TALK_2,...]         The names of the talks to be transitioned.
  --state [Submitted, Rejected, ...]  The new state of the talks.

NOTES

  - This script will not log into Papercall for you. You'll need to do it from a browser.
    Before running this script, do the following:

    1. Log into PaperCall at https://papercall.io
    2. Once logged in, open Chrome Dev Tools or Firefox Web Tools, then click on the "Network" tab.
    3. Visit "https://www.papercall.io/me".
    4. Click on the _first_ request to PaperCall, then search for _Cookie_ on the right.
    5. Copy that cookie, then save it into a file called \`.papercall_cookie\` in the
       directory this script is in.
USAGE
}

_log_debug() {
  if grep -Eiq "^true" <<< "$DEBUG_MODE"
  then
    >&2 echo "DEBUG: $1"
  fi
}

_log() {
  >&2 echo "INFO: $1"
}

_request() {
  path=$(sed 's#^/##' <<< $1)
  url="https://www.papercall.io/$path"
  command="curl -s -H 'Cookie: $(cat $PAPERCALL_SESSION_COOKIE_FILE)' '$url'"
  command_hash=$(md5sum <<< $command | head -c 10)
  _log_debug "Executing PaperCall request $command_hash: $command"
  start_time=$(date +%s)
  response=$(eval $command)
  end_time=$(date +%s)
  duration_seconds=$((end_time-start_time))
  _log_debug "PaperCall request $command_hash completed in $duration_seconds seconds."
  _log_debug "PaperCall request $command_hash response: $response"
  echo "$response"
}

validate_session_cookie() {
  if ! grep -q "Logout" <<< "$(_request "/me")"
  then
    return 1
  fi
}

session_cookie_file_exists() {
  test -e "$PAPERCALL_SESSION_COOKIE_FILE"
}

if [ "$1" == "-h" ] || [ "$1" == "--help" ]
then
  usage
  exit 0
fi

if ! session_cookie_file_exists
then
  >&2 echo "ERROR: Cookie file not found at $PAPERCALL_SESSION_COOKIE_FILE"
  exit 1
fi

if ! validate_session_cookie
then
  >&2 echo "ERROR: The cookie at $PAPERCALL_SESSION_COOKIE_FILE has expired or is invalid.
Please log in at https://papercall.io, open Chrome Dev Tools/Firefox Web Tools,
retrieve a new cookie, and save it to $PAPERCALL_SESSION_COOKIE_FILE."
  exit 1
fi
