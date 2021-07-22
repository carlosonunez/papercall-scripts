#!/usr/bin/env bash
# vi: set ft=bash:
PAPERCALL_SESSION_COOKIE_FILE="${PAPERCALL_SESSION_COOKIE_FILE:-$PWD/.papercall_cookie}"
DEBUG_MODE="${DEBUG_MODE:-false}"
TRACE_MODE="${TRACE_MODE:-false}"
USER_AGENT='Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:90.0) Gecko/20100101 Firefox/90.0'

usage() {
  cat <<-USAGE
PAPERCALL_SESSION_COOKIE_FILE=\$file $(basename $0) [options]
Changes the state of one or more Papercall talks

ENVIRONMENT VARIABLES

  PAPERCALL_SESSION_COOKIE_FILE       The file containing your Papercall cookie.
                                      See "NOTES" for info on how to retrieve it.
                                      Defaults to $PWD/.papercall_cookie.
  DEBUG_MODE                          Show debug events.
  TRACE_MODE                          Show debug events and HTTP responses.

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

_htmlencode() {
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g' <<< "$1"
}

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

_next_arg_is_arg() {
  grep -Eiq -- '^--' <<< "$1"
}

_log_info() {
  >&2 echo "INFO: $1"
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

_put() {
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

event_id_from_name() {
  event_name="$1"
  _log_info "Resolving event ID for name or pattern: $event_name..."
  id=$(_request "/events/my" | \
    grep 'a href' | \
    grep -E '/events/[0-9]{1,}">\w' | \
    sed -E 's/^[ \t]+//' | \
    grep -E ">$event_name<" | \
    sed -E 's#^.*events/([0-9]{1,}).*#\1#')
  if test -z "$id"
  then
    _log_error "No ID found for any event matching pattern $event_name"
    return 1
  fi
  echo "$id"
}

get_matching_talks() {
  _last_page_of_cfps() {
    grep -q 'next disabled' <<< "$1" || ! grep -q 'next' <<< "$1"
  }

  _get_talk_states() {
    link="$1"
    _log_debug "Getting talk states for link $link"
    html=$(_request "$link?page=1")
    states=$(echo "$html" | grep -E 'data-state' | \
      sed -E 's/.*data-state="(.*)".*$/\1/')
    if test -z "$states"
    then
      _log_error "get_matching_talks: Unable to retrieve talk states from link: $link"
      return 1
    fi
    echo "$states"
  }

  _get_talks_in_page() {
    echo "$1" | grep -E "href.*submissions/[0-9]{1,}" | \
      sed -E "s/.*href=\"(.*)\"><strong>(.*)<\/strong.*$/\1,\2,talk_state:$2/g" | \
      sed -E 's/[ ]+,talk_state:/,talk_state:/g' | \
      sed "s/’/'/g" | \
      sed -E "s/[ ]+/ /g"
  }

  _get_cfp_link() {
    _log_debug "Getting CFP link for event id $1"
    cfps_link=$(_request "/events/$1/" | \
      grep -E "See all [0-9]{1,} Submissions" | \
      sed 's/.*href="\(.*\)">.*$/\1/' | \
      uniq)
    _log_debug "CFP link: $cfps_link"
    if test -z "$cfps_link"
    then
      _log_error "get_matching_talks: unable to find CFPs link for event $event_id"
      return 1
    fi
    echo "$cfps_link"
  }

  _get_authenticity_tokens() {
    html="$1"
    talk_data="$2"
    talks=""
    while read -r talk
    do
      link=$(awk -F',' '{print $1}' <<< "$talk")
      _log_debug "Looking for authenticity token belonging to resource $link"
      token=$(echo "$html" | \
        grep -E "action=\"$link\".*authenticity_token" | \
        sed -E 's/.*name="authenticity_token" value="(.*)".*$/\1/')
      if test -z "$token"
      then
        _log_error "No token found for resource $link"
        token="no_token"
      fi
      talks=$(printf "%s\n%s" "$talks" "$talk,authenticity_token:$token")
    done < <(echo "$talk_data" | grep -Ev '^$')
    echo "$talks"
  }

  _get_all_cfps() {
    link="$1"
    states="$2"
    talks=""
    auth_tokens=""
    for state in $states
    do
      page=1
      while true
      do
        _log_debug "Fetching talks from page $page in state $state..."
        cfps_in_page_html=$(_request "$link?page=$page&state=$state")
        if test -z "$cfps_in_page_html"
        then
          _log_error "get_matching_talks: No CFPs found inside of $link"
          return 1
        fi
        this_csv_without_tokens=$(_get_talks_in_page "$cfps_in_page_html" "$state")
        this_csv=$(_get_authenticity_tokens "$cfps_in_page_html" "$this_csv_without_tokens")
        talks=$(printf "%s\n%s" "$talks" "$this_csv")
        if _last_page_of_cfps "$cfps_in_page_html"
        then
          _log_debug "Found last page of talks in $link on page $page for state $state; breaking"
          break
        fi
        this_csv=""
        let page+=1
      done
    done
    echo "$talks"
  }
  
  _filter_talks() {
    all_talks="$1"
    pattern="$2"
    _log_debug "Filtering talks to those that match psv $pattern"
    matches=""
    while read -r talk
    do
      talk_htmlencoded=$(_htmlencode "$talk")
      _log_debug "Looking for $talk_htmlencoded in $all_talks"
      match=$(grep ",$talk_htmlencoded,talk_state:" <<< "$all_talks")
      if test -z "$match"
      then
        matches=$(printf "%s\n%s" "$matches" "nomatch,$talk")
      else
        matches=$(printf "%s\n%s" "$matches" "$match")
      fi
    done < <(tr '|' '\n' <<< "$pattern" | grep -Ev '^$')
    echo "$matches" | sort -u | grep -Ev '^$'
  }

  event_id="$1"
  talks="$2"
  _log_info "Fetching all talks for event ID $event_id..."
  cfp_link=$(_get_cfp_link "$event_id") || return 1
  talk_states=$(_get_talk_states "$cfp_link") || return 1
  cfps=$(_get_all_cfps "$cfp_link" "$talk_states") || return 1

  _filter_talks "$cfps" "$talks_psv"
}

change_talk_state_bulk() {
  matching_talks="$1"
  new_state="$(tr '[:upper:]' '[:lower:]' <<< $2)"
  while read -r talk
  do
    old_state=$(sed -E 's/.*talk_state:(.*),auth.*$/\1/' <<< "$talk")
    talk_name=$(sed -E 's/.*[0-9],(.*),talk_state.*$/\1/' <<< "$talk")
    talk_path=$(awk -F',' '{print $1}' <<< "$talk")
    authenticity_token=$(sed -E 's/.*authenticity_token:(.*)$/\1/' <<< "$talk")
    payload="utf8=%E2%9C%93&_method=put&authenticity_token=$authenticity_token&submission%5Bstate%5D=$old_state&submission%5Bstate%5D=$new_state"
    _log_info "Transitioning '$talk_name' with auth token '$authenticity_token' from '$old_state' to '$new_state' (this might take a while)"
    _put "$talk_path" "$payload" "$authenticity_token"
  done <<< "$matching_talks"
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

event_name=""
talks_psv=""
new_state=""

while test "$#" -gt 0
do
  case $1 in
    --event-name)
      shift
      ! _next_arg_is_arg "$1" && { event_name="$1"; shift; }
      ;;
    --talks)
      shift
      ! _next_arg_is_arg "$1" && { talks_psv="$1"; shift; }
      ;;
    --state)
      shift
      ! _next_arg_is_arg "$1" && { new_state="$1"; shift; }
      ;;
    *)
      usage
      >&2 echo "ERROR: Argument is invalid: $1"
      exit 1
      ;;
  esac
done

_verify_required_arg_or_fail "--event" "$event_name"
_verify_required_arg_or_fail "--state" "$new_state"
_verify_required_arg_or_fail "--talks" "$talks_psv"

if ! validate_session_cookie
then
  _fail "The cookie at $PAPERCALL_SESSION_COOKIE_FILE has expired or is invalid.
Please log in at https://papercall.io, open Chrome Dev Tools/Firefox Web Tools,
retrieve a new cookie, and save it to $PAPERCALL_SESSION_COOKIE_FILE."
fi

event_id=$(event_id_from_name "$event_name") || _fail "Event name not found: $event_name"
talks_data=$(get_matching_talks "$event_id" "$talks_psv")
_log_info "$(wc -l <<< "$talks_data") talks found."
matches=$(grep -v "nomatch" <<< "$talks_data")
non_matches=$(grep "nomatch" <<< "$talks_data")
test -z "$non_matches" || _fail "Some talks weren't found in your search: $non_matches"

change_talk_state_bulk "$matches" "$new_state"
