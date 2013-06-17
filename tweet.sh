#!/bin/bash
## vim:tabstop=8:shiftwidth=2
##
## Twitter client implemented in bash/ksh/zsh with openssl(1)
## Copyright (C) 2013 SATOH Fumiyasu @ OSS Technology Corp., Japan
##               <https://GitHub.com/fumiyas/Tweet.sh>
##               <https://Twitter.com/satoh_fumiyasu>
##               <http://www.OSSTech.co.jp/>
##
## License: GNU General Public License version 3
##
## Requirements:
##   * bash(1), ksh(1) or zsh(1)
##   * openssl(1)
##

set -u

function HTTP_pencode {
  if [[ -n ${1+set} ]]; then
    typeset in="${1-}"; shift
  else
    typeset in
    IFS= read -r in
  fi

  typeset LC_ALL='C'
  typeset out
  typeset char
  while [[ -n "$in" ]]; do
    char="${in:0:1}"
    case "$char" in
    [a-zA-Z0-9\-._~])
      out+="$char"
      ;;
    *)
      out+=$(printf '%%%02X' "'$char")
      ;;
    esac
    in="${in:1}"
  done

  echo -n "$out"
}

function OAuth_nonce {
  printf '%04x%04x%04x%04x%04x%04x%04x%04x' \
    $RANDOM \
    $RANDOM \
    $RANDOM \
    $RANDOM \
    $RANDOM \
    $RANDOM \
    $RANDOM \
    $RANDOM \
    ;
}

function OAuth_timestamp {
  date +%s
}

function OAuth_generate {
  typeset realm="$1"; shift
  typeset consumer_key="$1"; shift
  typeset consumer_secret="$1"; shift
  typeset access_token="$1"; shift
  typeset access_token_secret="$1"; shift
  typeset method="$1"; shift
  typeset url="$1"; shift

  typeset hmac_key="$consumer_secret&$access_token_secret"
  typeset -a oauth
  oauth=(
    "oauth_consumer_key=$consumer_key"
    "oauth_signature_method=HMAC-SHA1"
    "oauth_version=1.0"
    "oauth_nonce=$(OAuth_nonce)"
    "oauth_timestamp=$(OAuth_timestamp)"
    "oauth_token=$access_token"
  )

  typeset url_tmp
  typeset url_scheme="${url%%://*}"
  url_tmp="${url#*://}"
  typeset url_path="/${url_tmp#*/}"
  url_tmp="${url_tmp%%/*}"
  typeset url_host="${url_tmp%%:*}"

  typeset oauth_string=$(
    echo -n "$method&"
    HTTP_pencode "$url"
    echo -n '&'

    for pv in "$@" "${oauth[@]}"; do
      echo "$(HTTP_pencode "${pv%%=*}") $(HTTP_pencode "${pv#*=}")"
    done \
    |sort \
    |sed 's/ /%3D/;s/$/%26/' \
    |tr -d '\n' \
    |sed 's/%26$//' \
    ;
  )
  typeset oauth_signature=$(
    echo -n "$oauth_string" \
    |openssl sha1 -hmac "$hmac_key" -binary \
    |openssl base64 \
    |HTTP_pencode \
    ;
  )

  typeset query=
  while [[ $# -gt 0 ]]; do
    query+="$1"
    [[ $# -gt 1 ]] && query+='&'
    shift
  done
  if [[ $method != 'POST' ]]; then
    url="$url?$query"
    query=''
  fi

  echo "$method $url_path HTTP/1.1"
  echo "Host: $url_host"
  if [[ $method == 'POST' ]]; then
    echo 'Content-Type: application/x-www-form-urlencoded'
  fi

  echo Authorization: OAuth realm=$realm,
  typeset pv
  for pv in "${oauth[@]}"; do
    echo " $pv,"
  done
  echo " oauth_signature=$oauth_signature"
  echo "Connection: close"

  typeset LC_ALL='C'
  echo "Content-Length: ${#query}"
  echo
  echo -n "$query"
}

function Tweet_tweet {
  typeset script="$1"; shift

  if [[ ${#script} -gt 140 ]]; then
    ## FIXME: Print error message
    return 1
  fi

  OAuth_generate \
    'http://api.twitter.com' \
    "$oauth_consumer_key" \
    "$oauth_consumer_secret" \
    "$oauth_access_token" \
    "$oauth_access_token_secret" \
    "POST" \
    "https://api.twitter.com/1.1/statuses/update.json" \
    "status=$(HTTP_pencode "$script")" \
    ;
}

if [[ ${0##*/} == tweet ]] && [[ ${zsh_eval_context-toplevel} == toplevel ]]; then
  if [[ $# -ne 1 ]]; then
    echo "Usage: $0 SCRIPT"
    exit 0
  fi
  . "${TWEET_CONF-$HOME/.tweet.conf}" || exit 1
  Tweet_tweet "$@" |openssl s_client -crlf -quiet -connect api.twitter.com:443
  ## FIXME: Parse reply from Twitter.com
  exit $?
fi

return 0

