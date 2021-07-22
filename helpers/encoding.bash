#!/usr/bin/env bash
_htmlencode() {
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g' <<< "$1"
}

urlencode() {
  python -c "import urllib.parse;print (urllib.parse.quote(input()))" <<< "$1"
}
