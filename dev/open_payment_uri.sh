#!/usr/bin/env bash
set -euo pipefail

uri='zcash:ztestsapling10yy2ex5dcqkclhc7z7yrnjq2z6feyjad56ptwlfgmy77dmaqqrl9gyhprdx59qgmsnyfska2kez'
uri+='?amount=0.12345678'
uri+='&memo=Q1AtQzZDREI3NzU'
uri+='&message=Thank%20you%20for%20your%20purchase'

case "$(uname -s)" in
  Darwin)
    open "$uri"
    ;;
  Linux)
    xdg-open "$uri"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    cmd.exe /c start "" "$uri"
    ;;
  *)
    printf 'Unsupported platform for opening payment URI\n' >&2
    exit 1
    ;;
esac
