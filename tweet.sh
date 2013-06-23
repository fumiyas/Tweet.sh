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

if [[ -n ${ZSH_VERSION-} ]]; then
  setopt BSD_ECHO
elif [[ -n ${BASH_VERSION-} ]]; then
  shopt -u xpg_echo
else ## ksh
  if [[ $(echo -n) == -n ]]; then
    alias echo='print -r'
  fi
fi

Tweet_conf_file="${TWEET_CONF-$HOME/.tweet.conf}"
Tweet_api_host="api.twitter.com"
Tweet_api_port="443"
Tweet_api_url="https://$Tweet_api_host/1.1"
Tweet_api_url_request_token="https://$Tweet_api_host/oauth/request_token"
Tweet_api_url_authorize_token="https://$Tweet_api_host/oauth/authorize"
Tweet_api_url_access_token="https://$Tweet_api_host/oauth/access_token"
Tweet_oauth_consumer_key='RSwbFF0fObZEJMoZLK51w'
Tweet_oauth_consumer_secret='1oxAO6md2ls4FSXhHBnosMD8crNyYZgdzUHlZvNlaU'
Tweet_oauth_access_token=''
Tweet_oauth_access_token_secret=''
Tweet_c_cr="
"

function HTTP_browser {
  typeset url="$1"; shift
  typeset open=

  case $(uname) in
  Darwin)
    open="open"
    ;;
  CYGWIN_*)
    open="cygstart"
    ;;
  *)
    if [[ -f /etc/debian_version ]]; then
      open="sensible-browser"
    elif type xdg-open >/dev/null 2>&1; then
      open="xdg-open"
    elif [[ ${XDG_CURRENT_DESKTOP-} == GNOME || -n ${GNOME_DESKTOP_SESSION_ID-} ]] ; then
      open="gnome-open"
    elif [[ ${XDG_CURRENT_DESKTOP-} == KDE || ${KDE_FULL_SESSION-} == true ]] ; then
      open="kde-open"
    else
      typeset browsers="${BROWSER-}"
      if [[ -z $browsers ]]; then
	browsers="www-browser:links2:elinks:links:lynx:w3m"
	if [[ -n ${DISPLAY-} ]]; then
	  browsers="x-www-browser:firefox:seamonkey:mozilla:epiphany:konqueror:chromium-browser:google-chrome:$browsers"
	fi
      fi

      typeset ifs_save="$IFS"
      typeset found=
      IFS=:
      for open in $browsers; do
	if type "$open" >/dev/null 2>&1; then
	  found=set
	  break
	fi
      done
      IFS="$ifs_save"

      if [[ -z $found ]]; then
	## FIXME: Print error message
	return 1
      fi
    fi
    ;;
  esac

  "$open" "$url"

  return $?
}


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

function HTTP_pdecode {
  typeset in="${1//\\/\\\\}"; shift

  printf "${in//\%/\\x}"
}

function HTTP_request {
  typeset line
  typeset -l line_lower
  typeset cert_status= http_ver= rcode= rmessage= content_type= body=

  {
    while IFS= read -r line; do
      line="${line%}"
      if [[ $line == 'verify return:0' ]]; then
	cert_status='verified'
	break
      fi
    done

    read -r http_ver rcode rmessage
    while IFS= read -r line; do
      line="${line%}"
      [[ -z $line ]] && break
      line_lower="$line"
      case "$line_lower" in
      content-type:*)
	content_type="${line#*: }"
	;;
      esac
    done
    while IFS= read -r line; do
      body+="$line$Tweet_c_cr"
    done
    body+="$line"
  } < <(
    openssl s_client \
      -crlf \
      -quiet \
      -connect "$Tweet_api_host:$Tweet_api_port" \
      2>&1 \
      ;
  )

  echo "$cert_status"
  echo "$rcode"
  echo "$rmessage"
  echo "$content_type"
  echo -n "$body"
}

function HTTP_response_extract {
  typeset response="$1"; shift
  typeset name="$1"; shift
  typeset value=

  value="${response#*\&$name=}"
  value="${value#$name=}"
  if [[ $value == $response ]]; then
    return 1
  fi
  value="${value%%\&*}"

  echo -n "$value"
  return 0
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
  typeset token="$1"; shift
  typeset token_secret="$1"; shift
  typeset callback="$1"; shift
  typeset method="$1"; shift
  typeset url="$1"; shift

  typeset hmac_key="$consumer_secret&$token_secret"
  typeset -a oauth
  oauth=(
    "oauth_consumer_key=$consumer_key"
    "oauth_signature_method=HMAC-SHA1"
    "oauth_version=1.0"
    "oauth_nonce=$(OAuth_nonce)"
    "oauth_timestamp=$(OAuth_timestamp)"
    ${token:+"oauth_token=$token"}
    ${callback:+"oauth_callback=$callback"}
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

  echo Authorization: OAuth${realm:+ realm=$realm,}
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

function Tweet_init {
  :
}

function Tweet_authorize {
  if [[ -n $Tweet_oauth_access_token && -n $Tweet_oauth_access_token_secret ]]; then
    return 0
  fi

  typeset cert_status= rcode= rmessage= content_type= body=

  echo "No OAuth access token and/or secret for Twitter access configured."
  echo "I'll open Twitter site by a WWW browser to get OAuth access token"
  echo "and secret. Please authorize this application on Twitter site!!"
  echo
  echo "Press Enter key to open Twitter site..."
  read

  {
    IFS= read -r cert_status
    IFS= read -r rcode
    IFS= read -r rmessage
    IFS= read -r content_type
    IFS= read -r body
  } < <(
    OAuth_generate \
      "$Tweet_api_url" \
      "$Tweet_oauth_consumer_key" \
      "$Tweet_oauth_consumer_secret" \
      '' \
      '' \
      '' \
      "POST" \
      "$Tweet_api_url_request_token" \
    |HTTP_request \
  )
  if [[ $cert_status != 'verified' ]]; then
    ## FIXME: Print error message
    return 1
  fi
  if [[ $rcode != 200 ]]; then
    ## FIXME: Print error message
    return 1
  fi

  typeset oauth_token=$(HTTP_response_extract "$body" oauth_token)
  typeset oauth_token_secret=$(HTTP_response_extract "$body" oauth_token_secret)

  HTTP_browser "$Tweet_api_url_authorize_token?oauth_token=$oauth_token"

  echo -n 'Enter PIN: '
  typeset pin=
  read -r pin

  {
    IFS= read -r cert_status
    IFS= read -r rcode
    IFS= read -r rmessage
    IFS= read -r content_type
    IFS= read -r body
  } < <(
    OAuth_generate \
      "$Tweet_api_url" \
      "$Tweet_oauth_consumer_key" \
      "$Tweet_oauth_consumer_secret" \
      "$oauth_token" \
      "$oauth_token_secret" \
      '' \
      "POST" \
      "$Tweet_api_url_access_token" \
      "oauth_verifier=$pin" \
    |HTTP_request \
  )
  if [[ $cert_status != 'verified' ]]; then
    ## FIXME: Print error message
    return 1
  fi
  if [[ $rcode != 200 ]]; then
    ## FIXME: Print error message
    return 1
  fi

  Tweet_oauth_access_token=$(HTTP_response_extract "$body" oauth_token)
  Tweet_oauth_access_token_secret=$(HTTP_response_extract "$body" oauth_token_secret)

  if [[ ! -f "$Tweet_conf_file" ]]; then
    (umask 0077; touch "$Tweet_conf_file") || return 1
    echo "oauth_consumer_key='$Tweet_oauth_consumer_key'" >>"$Tweet_conf_file"
    echo "oauth_consumer_secret='$Tweet_oauth_consumer_secret'" >>"$Tweet_conf_file"
  fi
  echo "oauth_access_token='$Tweet_oauth_access_token'" >>"$Tweet_conf_file"
  echo "oauth_access_token_secret='$Tweet_oauth_access_token_secret'" >>"$Tweet_conf_file"

  return 0
}

function Tweet_tweet {
  typeset script="$1"; shift

  if [[ ${#script} -gt 140 ]]; then
    ## FIXME: Print error message
    return 1
  fi

  OAuth_generate \
    "$Tweet_api_url" \
    "$Tweet_oauth_consumer_key" \
    "$Tweet_oauth_consumer_secret" \
    "$Tweet_oauth_access_token" \
    "$Tweet_oauth_access_token_secret" \
    '' \
    "POST" \
    "$Tweet_api_url/statuses/update.json" \
    "status=$(HTTP_pencode "$script")" \
    ;
}

function Tweet_command_help {
  if [[ $# -ne 1 ]]; then
    echo "Usage: $0 SCRIPT"
    exit 0
  fi
}

function Tweet_command {
  . "$Tweet_conf_file" || exit 1

  if [[ -n ${oauth_consumer_key-} ]]; then
    Tweet_oauth_consumer_key="$oauth_consumer_key"
  fi
  if [[ -n ${oauth_consumer_secret-} ]]; then
    Tweet_oauth_consumer_secret="$oauth_consumer_secret"
  fi
  if [[ -n ${oauth_access_token-} ]]; then
    Tweet_oauth_access_token="$oauth_access_token"
  fi
  if [[ -n ${oauth_access_token_secret-} ]]; then
    Tweet_oauth_access_token_secret="$oauth_access_token_secret"
  fi

  Tweet_authorize
  Tweet_tweet "$@" |openssl s_client -crlf -quiet -connect "$Tweet_api_host:$Tweet_api_port"
  ## FIXME: Parse reply from Twitter.com
  return $?
}

if [[ ${0##*/} == tweet ]] && [[ ${zsh_eval_context-toplevel} == toplevel ]]; then
  Tweet_init
  Tweet_command "$@"
  exit $?
fi

return 0

