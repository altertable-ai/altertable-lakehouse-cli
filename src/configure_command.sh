# Dispatch configure modes. Behavior lives in src/lib/configure.sh.
if [[ -n "${args[--list]:-}" ]]; then
  configure_run_list
elif [[ -n "${args[--remove]:-}" ]]; then
  configure_run_remove
elif [[ -n "${args[--clear]:-}" ]]; then
  configure_run_clear
else
  configure_run_set
fi
