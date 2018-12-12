#!/usr/bin/env bash

set -e

functions=()
bat="${BASH_SOURCE[0]}"

color_prompt="\033[38;5;240m"
color_exec="\033[38;5;6m"
color_function="\033[38;5;063m"
color_params="\033[1;3;38;5;242m"
color_docstring="\033[3;38;5;242m"
color_eval="\033[38;5;244m"
color_reset="\033[0m"

upsearch () {
  local directory="$PWD"
  while [ -n "$directory" ]; do
    if [ -e "$directory/$1" ]; then
      printf "$directory/$1"
      return 0
    fi
    directory=${directory%/*}
  done
  return 1
}

# Return 0 if element $1 is matched by any of the successive arguments
contains () {
  local match="$1"
  shift
  [[ " $@ " =~ " $match " ]]
}

list_file_functions () {
  local docstring=()
  local re_comment='^[[:space:]]*#.*'
  local re_function='^([a-zA-Z_][a-zA-Z_0-9_]*)[[:space:]]*\(\)[[:space:]]*{.*'
  while read -r line; do
    if [[ $line =~ $re_comment ]]; then
      docstring+=("${line#*#}")
    elif [[ $line =~ $re_function ]]; then
      l=$(( ${#BASH_REMATCH[@]} - 1 ))
      f=${BASH_REMATCH[l]}
      if contains "${f}" "${functions[@]}" ; then
        printf "$color_function$f$color_reset\n"
        [ "${docstring[*]}" ] && printf "$color_docstring %s\n$color_reset" "${docstring[@]}"
      fi
      docstring=()
    else
      docstring=()
    fi
  done <"$1"
}

# List the commands defined in the current `bat.config` file
list () {
  list_file_functions "$config_file"
}

# Display usage information and list the available commands
help () {
  cat <<EOF
Bash Automation Tool

  usage: bat [<command> [arguments...]...]

  Commands are sourced from a bat.config file, normally placed in the project
  root directory. If no command is specified, the first command is run.

  The built in commands are:

EOF
  list_file_functions "$bat"
}

# Get last character of string
last_char () {
  local i=$((${#1}-1))
  echo "${1:$i:1}"
}

join_by () {
  separator="$1"
  shift
  ret="$( printf "${separator}%s" "$@" )"
  ret="${ret:${#separator}}" # remove leading separator
  echo "$ret"
}

# Run commands in parallel. All output goes to STDOUT
parallel () {
  echo BAT: Starting processes...

  for cmd in "$@"; do
    echo BAT: starting process: $cmd
    $cmd & pid=$!
    PID_LIST+=" $pid"
  done

  trap "kill $PID_LIST" SIGINT

  echo BAT: All parallel processes have started.

  wait $PID_LIST

  echo
  echo BAT: All processes have completed.
}

print_and_eval () {
  printf "$color_prompt\$ $color_eval%s" "$1"
  [ $# -gt 1 ] && printf " ..."
  printf "$color_reset\n"
  eval "$(join_by $'\n' "$@")"
}

# Print and eval each expression defined in the given function
print_and_eval_function () {
  local re_function_or_bracket='^([a-zA-Z_][a-zA-Z_0-9]* \(\))|\{|\}'
  local f="$1"
  shift
  if contains "$f" "${builtin_functions[@]}"; then
    "$f" "$@"
  else
    expression=()
    while read -r line; do
      [[ $line =~ $re_function_or_bracket ]] && continue
      expression+=( "$line" )
      if [ "$(last_char "$line")" = ";" ]; then
        print_and_eval "${expression[@]}"
        local err=$?
        [ $err -eq 0 ] || exit $err
        expression=()
      fi
    done <<<"$(declare -f $f)"
    print_and_eval "${expression[@]}"
  fi
}

# Command line parameters are evaluated as functions if they are contained in
# the `functions` array. Otherwise, they are passed as arguments to the
# preceding function.
function_loop () {
  while [ "$*" ]; do
    f=$1
    if ! contains "$f" "${functions[@]}"; then
      echo "Aborting because the function ($f) does not exist. Use \`bat help\` to learn more."
      exit 27
    fi
    shift
    params=()
    while [ "$*" ] && ! contains "$1" "${functions[@]}" ; do
      params+=("$1")
      shift
    done
    printf ">> $color_exec%s $color_params%s$color_reset\n" "$f" "$params"
    print_and_eval_function $f "${params[@]}"
    local err=$?
    if [ $err -ne 0 ]; then
      echo "Aborting because the function ($cmd) encountered an error"
      exit $err
    fi
  done
}

# Locate bat.config
if [ -e "$1" ] && [ "$(basename $1)" = "bat.config" ]; then
  config_file="$1"
  bat_dir="$(cd (dirname "$1") && pwd)"
  shift
elif [ -e "$1/bat.config" ]; then
  config_file="$1/bat.config"
  shift
elif config_file="$(upsearch bat.config)"; then
  bat_dir="$(dirname "$config_file")"
else
  "$log_error" bat.config file not found; exiting.
  exit -127
fi

functions=()

. "$config_file"
[ "${functions[*]}" ] || \
  functions=( $(awk '/^[a-zA-Z_][0-9a-zA-Z_]*[ ]+\(\)[ ]*{?$/ {print $1}' "$config_file" 2>/dev/null) )

builtin_functions=( help list )
functions+=( "${builtin_functions[@]}" )

if [ "$*" ]; then
  args=("$@")
else
  args=( "${functions[0]}" )
fi

pushd "$bat_dir" >/dev/null

function_loop "${args[@]}"

popd >/dev/null
