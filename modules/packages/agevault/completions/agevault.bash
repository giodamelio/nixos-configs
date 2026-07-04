# Thin stub: agevault's `__complete` backend computes every candidate level
# (subcommands, then dynamic host and secret names). We pass only the
# already-completed words; bash filters by the typed prefix. Logic lives in
# modules/packages/agevault/agevault.nu, never here.
_agevault() {
  local cur line out files=0
  local -a pre vals
  cur="${COMP_WORDS[COMP_CWORD]}"
  pre=("${COMP_WORDS[@]:1:COMP_CWORD-1}")
  out=$(agevault __complete "${pre[@]}" 2>/dev/null)

  while IFS= read -r line; do
    [[ -z $line ]] && continue
    if [[ $line == '%files' ]]; then
      files=1
      continue
    fi
    vals+=("${line%%$'\t'*}")
  done <<<"$out"

  mapfile -t COMPREPLY < <(compgen -W "${vals[*]}" -- "$cur")
  if ((files)); then
    local f
    while IFS= read -r f; do COMPREPLY+=("$f"); done < <(compgen -f -- "$cur")
  fi
}
complete -F _agevault agevault
