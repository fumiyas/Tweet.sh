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
  setopt KSH_GLOB
  setopt TYPESET_SILENT
elif [[ -n ${BASH_VERSION-} ]]; then
  shopt -u xpg_echo
else ## ksh
  if [[ $(echo -n) == -n ]]; then
    alias echo='print -r'
  fi
fi

Tweet_conf_file="${TWEET_CONF-$HOME/.tweet.conf}"
Tweet_api_host="api.twitter.com"
Tweet_api_url="https://$Tweet_api_host/1.1"
Tweet_api_url_request_token="https://$Tweet_api_host/oauth/request_token"
Tweet_api_url_authorize_token="https://$Tweet_api_host/oauth/authorize"
Tweet_api_url_access_token="https://$Tweet_api_host/oauth/access_token"
Tweet_oauth_consumer_key='C7IpNPso1IYdCweXYaJ0Q'
Tweet_oauth_consumer_secret='LAsLscqNC4kBaDW8EtmxMIVCkY8nsw07NaN5PNBYuY'
Tweet_oauth_access_token=''
Tweet_oauth_access_token_secret=''
Tweet_script_limit='140'
Tweet_c_cr="
"

function Tweet_error {
  echo "${Tweet_command_name-Tweet}: ERROR: $1" 1>&2
}

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
  typeset out=
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

function HTTPS_request {
  typeset url="$1"; shift
  typeset method="$1"; shift

  typeset url_tmp
  typeset url_scheme="${url%%://*}"
  url_tmp="${url#*://}"
  typeset url_path="/${url_tmp#*/}"
  url_tmp="${url_tmp%%/*}"
  typeset url_host="${url_tmp%%:*}"
  if [[ $url_tmp == @(*:*) ]]; then
    typeset url_port="${url_tmp#*:}"
  else
    typeset url_port='443'
  fi

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
    {
      echo "$method $url_path HTTP/1.1"
      echo "Host: $url_host"
      echo "Connection: close"
      if [[ $method == 'POST' ]]; then
	echo 'Content-Type: application/x-www-form-urlencoded'
      fi
      while [[ $# -gt 0 ]]; do
	[[ $1 == '--' ]] && { shift; break; }
	echo "$1"
	shift
      done
      typeset query="${1-}"
      typeset LC_ALL='C'
      echo "Content-Length: ${#query}"
      echo
      echo -n "$query"
    } \
    |openssl s_client \
      -crlf \
      -quiet \
      -connect "$url_host:$url_port" \
      2>&1 \
      ;
  )

  typeset ret='0'

  if [[ $cert_status != 'verified' ]]; then
    rcode='500'
    rmessage='Invalid server certificate'
    ret='1'
  elif [[ $rcode != 200 ]]; then
    ret='1'
  fi

  echo "$rcode $rmessage"
  echo "$content_type"
  echo
  echo -n "$body"

  return "$ret"
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
  typeset url="$1"; shift
  typeset method="$1"; shift

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

  typeset oauth_string
  oauth_string=$(
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
  typeset oauth_signature
  oauth_signature=$(
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

  echo "Authorization: OAuth${realm:+ realm=$realm,}"
  typeset pv
  for pv in "${oauth[@]}"; do
    echo " $pv,"
  done
  echo " oauth_signature=$oauth_signature"
}

function Tweet_init {
  :
}

function Tweet_authorize {
  if [[ -n $Tweet_oauth_access_token && -n $Tweet_oauth_access_token_secret ]]; then
    return 0
  fi

  echo "No OAuth access token and/or secret for Twitter access configured."
  echo
  echo "I'll open Twitter site by a WWW browser to get OAuth access token"
  echo "and secret. Please authorize this application and get a PIN code"
  echo "on Twitter site."
  echo
  echo -n "Press Enter key to open Twitter site..."
  read
  echo

  typeset oauth
  oauth=$(
    OAuth_generate \
      "$Tweet_api_url" \
      "$Tweet_oauth_consumer_key" \
      "$Tweet_oauth_consumer_secret" \
      '' \
      '' \
      '' \
      "$Tweet_api_url_request_token" \
      "POST" \
      ;
  )

  typeset response
  response=$(
    HTTPS_request \
      "$Tweet_api_url_request_token" \
      "POST" \
      "$oauth" \
      ;
  )
  typeset ret="$?"
  if [[ $ret -ne 0 ]]; then
    Tweet_error "OAuth request token failed: ${response%%$Tweet_c_cr*}"
    return 1
  fi

  typeset body="${response#*$Tweet_c_cr$Tweet_c_cr}"
  typeset oauth_token=$(HTTP_response_extract "$body" oauth_token)
  typeset oauth_token_secret=$(HTTP_response_extract "$body" oauth_token_secret)

  HTTP_browser "$Tweet_api_url_authorize_token?oauth_token=$oauth_token"

  echo -n 'Enter PIN code: '
  typeset pin=
  read -r pin
  echo

  typeset oauth
  oauth=$(
    OAuth_generate \
      "$Tweet_api_url" \
      "$Tweet_oauth_consumer_key" \
      "$Tweet_oauth_consumer_secret" \
      "$oauth_token" \
      "$oauth_token_secret" \
      '' \
      "$Tweet_api_url_access_token" \
      "POST" \
      "oauth_verifier=$pin" \
      ;
  )

  typeset response
  response=$(
    HTTPS_request \
      "$Tweet_api_url_access_token" \
      "POST" \
      "$oauth" \
      -- \
      "oauth_verifier=$pin" \
      ;
  )
  typeset ret="$?"
  if [[ $ret -ne 0 ]]; then
    Tweet_error "OAuth access token failed: ${response%%$Tweet_c_cr*}"
    return 1
  fi

  typeset body="${response#*$Tweet_c_cr$Tweet_c_cr}"
  Tweet_oauth_access_token=$(HTTP_response_extract "$body" oauth_token)
  Tweet_oauth_access_token_secret=$(HTTP_response_extract "$body" oauth_token_secret)

  if [[ ! -f "$Tweet_conf_file" ]]; then
    echo "Saving OAuth consumer key and secret into $Tweet_conf_file..."
    (umask 0077; touch "$Tweet_conf_file") || return 1
    echo "oauth_consumer_key='$Tweet_oauth_consumer_key'" >>"$Tweet_conf_file"
    echo "oauth_consumer_secret='$Tweet_oauth_consumer_secret'" >>"$Tweet_conf_file"
  fi
  echo "Saving OAuth access token and secret into $Tweet_conf_file..."
  echo "oauth_access_token='$Tweet_oauth_access_token'" >>"$Tweet_conf_file"
  echo "oauth_access_token_secret='$Tweet_oauth_access_token_secret'" >>"$Tweet_conf_file"

  return 0
}

function Tweet_tweet {
  typeset script="$1"; shift

  if [[ ${#script} -gt $Tweet_script_limit ]]; then
    Tweet_error "Script too long (>$Tweet_script_limit): ${#script}"
    return 1
  fi

  typeset query
  query="status=$(HTTP_pencode "$script")"

  typeset oauth
  oauth=$(
    OAuth_generate \
      "$Tweet_api_url" \
      "$Tweet_oauth_consumer_key" \
      "$Tweet_oauth_consumer_secret" \
      "$Tweet_oauth_access_token" \
      "$Tweet_oauth_access_token_secret" \
      '' \
      "$Tweet_api_url/statuses/update.json" \
      "POST" \
      "$query" \
      ;
  )

  typeset response
  response=$(
    HTTPS_request \
      "$Tweet_api_url/statuses/update.json" \
      "POST" \
      "$oauth" \
      -- \
      "$query" \
      ;
  )
  typeset ret="$?"
  if [[ $ret -ne 0 ]]; then
    Tweet_error "Tweet failed: ${response%%$Tweet_c_cr*}"
    return 1
  fi

  typeset body="${response#*$Tweet_c_cr$Tweet_c_cr}"
}

function Tweet_command_help {
  echo "Usage: $0 SCRIPT"
  exit 0
}

function Tweet_command {
  if [[ $# -ne 1 ]]; then
    Tweet_command_help
    exit 0
  fi

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

  Tweet_authorize && Tweet_tweet "$@"
  ## FIXME: Parse reply from Twitter.com
  return $?
}

if [[ ${0##*/} == tweet ]] && [[ ${zsh_eval_context-toplevel} == toplevel ]]; then
  Tweet_command_name="$0"
  Tweet_init
  Tweet_command "$@"
  exit $?
fi

return 0

