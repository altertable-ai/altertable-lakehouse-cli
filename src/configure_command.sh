# Dispatch configure modes. Behavior lives in src/lib/configure.sh.
if [[ -n "${args[--list]:-}" ]]; then
  configure_run_list
elif [[ -n "${args[--remove]:-}" ]]; then
  configure_run_remove
else
  configure_run_set
fi
