#!/usr/bin/env bash
# vi: set ft=bash:
#shellcheck disable=SC1090
for file in helpers/*.bash
do
  source "$file"
done

#No return values are being provided here. Disabling this cop.
#shellcheck disable=SC2155
export USAGE_TEXT=$(cat <<-USAGE
PAPERCALL_SESSION_COOKIE_FILE=\$file $(basename "$0") [options]
Notifies speakers about the status of their talks.

ENVIRONMENT VARIABLES

  PAPERCALL_SESSION_COOKIE_FILE       The file containing your Papercall cookie.
                                      See "NOTES" for info on how to retrieve it.
                                      Defaults to $PWD/.papercall_cookie.
  DEBUG_MODE                          Show debug events.
  TRACE_MODE                          Show debug events and HTTP responses.

OPTIONS

  --event-name [NAME]                 The name of the event in which the talks are located.
  --talks [TALK_1,TALK_2,...]         The names of the talks to be transitioned.
                                      Use to individually message CFP authors.
  --state [Submitted, Rejected, ...]  The state of talks whose authors need notification.

NOTES

  - You will need to have templates for each talk state that you'd like to send notifications for.
    These templates will need to be located in 'templates/'

    For instance, you'll need a file called 'templates/accepted.md' in order to send
    notifications to any CFPs that have been accepted.

    The templates must follow PaperCall's syntax format.

  - This script will not log into Papercall for you. You will need to do it from a browser.
    Before running this script, do the following:

    1. Log into PaperCall at https://papercall.io
    2. Once logged in, open Chrome Dev Tools or Firefox Web Tools, then click on the "Network" tab.
    3. Visit "https://www.papercall.io/me".
    4. Click on the _first_ request to PaperCall, then search for _Cookie_ on the right.
    5. Copy that cookie, then save it into a file called \`.papercall_cookie\` in the
       directory this script is in.
USAGE
)

show_usage_if_requested "$1"

if ! session_cookie_file_exists
then
  >&2 echo "ERROR: Cookie file not found at $PAPERCALL_SESSION_COOKIE_FILE"
  exit 1
fi

event_name=""
talks_psv=""
state=""

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
    --state) shift ! _next_arg_is_arg "$1" && { state="$1"; shift; } ;;
    *)
      usage
      >&2 echo "ERROR: Argument is invalid: $1"
      exit 1
      ;;
  esac
done

_verify_required_arg_or_fail "--event" "$event_name"
_verify_required_arg_or_fail "--state" "$state"
_verify_required_arg_or_fail "--talks" "$talks_psv"

if ! validate_session_cookie
then
  _fail "The cookie at $PAPERCALL_SESSION_COOKIE_FILE has expired or is invalid.
Please log in at https://papercall.io, open Chrome Dev Tools/Firefox Web Tools,
retrieve a new cookie, and save it to $PAPERCALL_SESSION_COOKIE_FILE."
fi

event_id=$(event_id_from_name "$event_name") || _fail "Event name not found: $event_name"
if ! test -z "$talks_psv"
then
  talks_data=$(get_matching_talks "$event_id" "$talks_psv")
  _log_info "$(wc -l <<< "$talks_data") talks found matching '$talks_psv'."
  matches=$(grep -v "nomatch" <<< "$talks_data")
  non_matches=$(grep "nomatch" <<< "$talks_data")
  test -z "$non_matches" || _fail "Some talks weren't found in your search: $non_matches"
else
  talks_data=$(get_all_talks "$event_id" | grep "talk_state:$state")
fi
_log_info "$(wc -l <<< "$talks_data") talks found matching '$talks_psv'."
notify_speakers "$talks_data"
