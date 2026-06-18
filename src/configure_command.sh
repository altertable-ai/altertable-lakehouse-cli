# Dispatch configure modes. Behavior lives in src/lib/configure.sh.
if [[ -n "${args[--show]:-}" ]]; then
  configure_run_show
elif [[ -n "${args[--clear]:-}" ]]; then
  configure_run_clear
else
  configure_run_set
fi
