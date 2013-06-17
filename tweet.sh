#!/bin/bash

set -u

function __generate_nonce {
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

function __time {
  date +%s
}

function __pencode {
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

function __hash {
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
    "oauth_nonce=$(__generate_nonce)"
    "oauth_timestamp=$(__time)"
    "oauth_token=$access_token"
  )

  typeset url_tmp
  typeset url_scheme="${url%%://*}"
  url_tmp="${url#*://}"
  typeset url_path="/${url_tmp#*/}"
  url_tmp="${url_tmp%%/*}"
  typeset url_host="${url_tmp%%:*}"

  echo "$method $url_path HTTP/1.1"
  echo "Host: $url_host"
  if [[ $method == 'POST' ]]; then
    echo 'Content-Type: application/x-www-form-urlencoded'
  fi

  echo 'Authorization: OAuth realm="http://api.twitter.com",'
  typeset pv
  for pv in "${oauth[@]}"; do
    echo " $pv,"
  done
  echo -n ' oauth_signature='

  {
    echo -n "$method&"
    __pencode "$url"
    echo -n '&'

    for pv in "$@" "${oauth[@]}"; do
      echo "$(__pencode "${pv%%=*}") $(__pencode "${pv#*=}")"
    done \
    |sort \
    |sed 's/ /%3D/;s/$/%26/' \
    |tr -d '\n' \
    |sed 's/%26$//' \
    ;
  } \
  |openssl sha1 -hmac "$hmac_key" -binary \
  |openssl base64 \
  |__pencode \
  ;
  echo
}

function __tweet {
  typeset script="$1"; shift

  set -- "status=$(__pencode "$script")"

  __hash \
    "$oauth_consumer_key" \
    "$oauth_consumer_secret" \
    "$oauth_access_token" \
    "$oauth_access_token_secret" \
    "POST" \
    "https://api.twitter.com/1.1/statuses/update.json" \
    "$@" \
    ;

  typeset body
  while [[ $# -gt 0 ]]; do
    body+="$1"
    [[ $# -gt 1 ]] && body+='&'
    shift
  done

  typeset LC_ALL='C'
  echo "Content-Length: ${#body}"
  echo "Connection: close"
  echo
  echo -n "$body"
}

if [[ ${0##*/} == tweet ]] && [[ ${zsh_eval_context-toplevel} == toplevel ]]; then
  if [[ $# -ne 1 ]]; then
    echo "Usage: $0 SCRIPT"
    exit 0
  fi
  . "${TWEET_SH_CONF-$HOME/.tweet.conf}"
  __tweet "$@" |openssl s_client -crlf -quiet -connect api.twitter.com:443
  exit $?
fi

return 0

