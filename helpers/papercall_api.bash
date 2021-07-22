#!/usr/bin/env bash
PAPERCALL_SESSION_COOKIE_FILE="${PAPERCALL_SESSION_COOKIE_FILE:-$PWD/.papercall_cookie}"
USER_AGENT='Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:90.0) Gecko/20100101 Firefox/90.0'

_post() {
  # Papercall uses a POST to perform a PUT action against talks. They even provide
  # the actual method inside of the payload instead of using it in the request!
  # So weird.
  path=$(sed 's#^/##' <<< $1)
  data="$2"
  csrf_token="$3"
  url="https://www.papercall.io/$path"
  command="curl -X POST -H 'Origin: https://www.papercall.io' \
-H 'X-CSRF-Token: $csrf_token' \
--data-raw '$data' --user-agent '$USER_AGENT' \
-s -H 'Cookie: $(cat $PAPERCALL_SESSION_COOKIE_FILE)' '$url'"
  command_hash=$(md5sum <<< $command | head -c 10)
  _log_debug "Executing PaperCall request $command_hash: $command"
  start_time=$(date +%s)
  response=$(eval $command)
  end_time=$(date +%s)
  duration_seconds=$((end_time-start_time))
  _log_debug "PaperCall request $command_hash completed in $duration_seconds seconds."
  _log_trace "PaperCall request $command_hash response: $response"
  echo "$response"
}

_request() {
  path=$(sed 's#^/##' <<< $1)
  url="https://www.papercall.io/$path"
  command="curl --user-agent '$USER_AGENT' -s -H 'Cookie: $(cat $PAPERCALL_SESSION_COOKIE_FILE)' '$url'"
  command_hash=$(md5sum <<< $command | head -c 10)
  _log_debug "Executing PaperCall request $command_hash: $command"
  start_time=$(date +%s)
  response=$(eval $command)
  end_time=$(date +%s)
  duration_seconds=$((end_time-start_time))
  _log_debug "PaperCall request $command_hash completed in $duration_seconds seconds."
  _log_trace "PaperCall request $command_hash response: $response"
  echo "$response"
}

validate_session_cookie() {
  _log_info "Validating your PaperCall session cookie..."
  if ! grep -q "Logout" <<< "$(_request "/me")"
  then
    return 1
  fi
}

session_cookie_file_exists() {
  test -e "$PAPERCALL_SESSION_COOKIE_FILE"
}
