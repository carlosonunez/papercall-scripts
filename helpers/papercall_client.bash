#!/usr/bin/env bash

# get_cfp_link_from_event_id: Generates the link to the set of CFPs for an event.
get_cfp_link_from_event_id() {
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

# event_id_from_name: Resolves a PaperCall event ID from a given name.
# The name can be a literal string or a regex.
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

# get_talks_from_event_id: Retrieves all talks from a provided PaperCall
# event ID. Talk names are returned with modifications; see
# _get_talks_in_page for more details. CSRF tokens for each talk is
# also included in the response.
get_talks_from_event_id() {
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
  
  event_id="$1"
  _log_info "Fetching all talks for event ID $event_id..."
  cfp_link=$(get_cfp_link_from_event_id "$event_id") || return 1
  talk_states=$(_get_talk_states "$cfp_link") || return 1
  _get_all_cfps "$cfp_link" "$talk_states" || return 1
}

# get_csrf_token_from_talk: Returns the CSRF token for a talk.
get_csrf_token_from_talk() {
  sed -E 's/.*authenticity_token:(.*)$/\1/' <<< "$1"
}

# get_talk_name_from_talk: Returns the talk name from a talk.
get_talk_name_from_talk() {
  sed -E 's/.*[0-9],(.*),talk_state.*$/\1/' <<< "$1"
}

# get_talk_state_from_talk: Returns the talk state of the talk,
# such as 'submitted', 'rejected', etc.
get_talk_state_from_talk() {
  sed -E 's/.*talk_state:(.*),auth.*$/\1/' <<< "$1"
}

# get_talk_href_from_talk: Returns the relative URI for the talk.
# This can be provided to Papercall API methods as-is.
get_talk_href_from_talk() {
  awk -F',' '{print $1}' <<< "$1"
}

# get_matching_talks: Returns a list of talks from a PaperCall Event ID
# that match a set of pipe-separated talk names.
get_matching_talks() {
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
  talks_psv="$2"
  cfps=$(get_talks_from_event_id "$event_id") || return 1
  _filter_talks "$cfps" "$talks_psv"
}

# send_submission_notification: Sends an email to the submitter of a CFP
# with a provided template.
send_submission_notification() {
  event_id="$1"
  talks="$2"
  body="$(urlencode "$3")"
  echo "$talks" |
    while read -r talk
    do
      state=$(get_talk_state_from_talk "$talk")
      talk_name=$(get_talk_name_from_talk "$talk")
      talk_id=$(get_talk_id_from_talk "$talk")
      sub_notifications_path="$(get_cfp_link_from_event_id "$event_id")/submission_notifications"
      authenticity_token=$(get_csrf_token_from_talk "$talk")
      payload="utf8=%E2%9C%93&state=$state&submission_id=$talk_id&body=$body"
      _log_info "Notifying author of '$talk_name' that their talk has been '$state'"
      _post "$sub_notifications_path" "$payload" "$authenticity_token"
    done
}
