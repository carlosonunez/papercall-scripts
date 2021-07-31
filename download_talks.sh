#!/usr/bin/env bash
# vi: set ft=bash:
for file in helpers/*.bash
do
  source "$file"
done

export USAGE_TEXT=$(cat <<-USAGE
PAPERCALL_SESSION_COOKIE_FILE=\$file $(basename $0) [options]
Downloads talks in JSON or CSV format.

ENVIRONMENT VARIABLES

  FORMAT=[json|csv]                   Same as using --json or --csv.
  FILE_NAME=[name]                    Same as --file-name.
  PAPERCALL_SESSION_COOKIE_FILE       The file containing your Papercall cookie.
                                      See "NOTES" for info on how to retrieve it.
                                      Defaults to $PWD/.papercall_cookie.
  DEBUG_MODE                          Show debug events.
  TRACE_MODE                          Show debug events and HTTP responses.

OPTIONS

  --event-name [NAME]                 The name of the event in which the talks are located.
  --file-name [NAME]                  The name of the file into which the talks are saved.
                                      (Default: $PWD/talks)
  --json                              Download in JSON format. (Default)
  --csv                               Download in CSV format.

NOTES

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

format_is_valid() {
  grep -Eiq '^(json|csv)$' <<< "$1"
}

format_is_csv() {
  grep -Eiq '^csv$' <<< "$1"
}

show_usage_if_requested "$1"

if ! session_cookie_file_exists
then
  >&2 echo "ERROR: Cookie file not found at $PAPERCALL_SESSION_COOKIE_FILE"
  exit 1
fi

event_name=""
format="${FORMAT:-json}"
file_name="${FILE_NAME:-$PWD/talks}"

while test "$#" -gt 0
do
  case $1 in
    --event-name)
      shift
      ! _next_arg_is_arg "$1" && { event_name="$1"; shift; }
      ;;
    --file-name)
      shift
      ! _next_arg_is_arg "$1" && { file_name="$1"; shift; }
      ;;
    --json)
      # This is the default. NOP.
      shift
      ;;
    --csv)
      shift
      ! _next_arg_is_arg "$1" && { format="csv" ; shift; }
      ;;
    *)
      usage
      >&2 echo "ERROR: Argument is invalid: $1"
      exit 1
      ;;
  esac
done

_verify_required_arg_or_fail "--event" "$event_name"

if ! format_is_valid "$format"
then
  _fail "Format invalid; must be JSON or CSV: $format"
fi

if format_is_csv "$format"
then
  file_name="${file_name}.csv"
fi

if ! validate_session_cookie
then
  _fail "The cookie at $PAPERCALL_SESSION_COOKIE_FILE has expired or is invalid.
Please log in at https://papercall.io, open Chrome Dev Tools/Firefox Web Tools,
retrieve a new cookie, and save it to $PAPERCALL_SESSION_COOKIE_FILE."
fi

event_id=$(event_id_from_name "$event_name") || _fail "Event name not found: $event_name"
_log_info "Downloading talks from event ID $event_id..."
download_talks_from_event_id "$event_id"  "$file_name" "$format" && 
  _log_info "Talks downloaded to $file_name."
