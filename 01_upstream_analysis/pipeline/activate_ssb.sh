#!/usr/bin/env bash
# Source this file from Bash or Zsh. It does not change caller shell options.

_ssb_env="/opt/conda/envs/ssb-atlas-v2"
_ssb_micromamba="/opt/ssb-user/.local/bin/micromamba"
if [[ -n "${ZSH_VERSION:-}" ]]; then
  _ssb_shell="zsh"
else
  _ssb_shell="bash"
fi

if ! _ssb_hook="$("${_ssb_micromamba}" shell hook -s "${_ssb_shell}")"; then
  echo "Failed to initialize micromamba" >&2
  return 1 2>/dev/null || exit 1
fi
if ! eval "${_ssb_hook}"; then
  echo "Failed to evaluate the micromamba shell hook" >&2
  return 1 2>/dev/null || exit 1
fi
if [[ "${CONDA_PREFIX:-}" != "${_ssb_env}" ]]; then
  if ! micromamba activate "${_ssb_env}"; then
    echo "Failed to activate ${_ssb_env}" >&2
    return 1 2>/dev/null || exit 1
  fi
fi
if ! source "/opt/ssb-pipeline/resources.env.sh"; then
  echo "Failed to load SSB resource paths" >&2
  return 1 2>/dev/null || exit 1
fi

echo "Activated SSB environment: ${_ssb_env}"
echo "SSB reference bundle: ${SSB_REFERENCE_BUNDLE}"
unset _ssb_env _ssb_micromamba _ssb_shell _ssb_hook
