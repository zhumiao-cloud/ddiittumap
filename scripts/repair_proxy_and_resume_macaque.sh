#!/usr/bin/env bash
set -euo pipefail
set +x
trap 'rc=$?; echo REPAIR_FAILED_LINE=$LINENO RC=$rc; exit $rc' ERR

test -n "${SXY_PSWD:-}"
sudo apt-get update -qq
sudo apt-get install -y -qq sshpass >/dev/null
install -d -m 700 "$HOME/.ssh"
ssh-keyscan -T 15 -p 20111 sxycloud1.top > "$HOME/.ssh/known_hosts" 2>/dev/null
chmod 600 "$HOME/.ssh/known_hosts"
export SSHPASS="$SXY_PSWD"

echo REPAIR_STAGE_UPLOAD
sshpass -e ssh -p 20111 -o StrictHostKeyChecking=yes -o ConnectTimeout=30 h3039@sxycloud1.top   'mkdir -p "$HOME/.local/libexec"'
sshpass -e scp -P 20111 -o StrictHostKeyChecking=yes   scripts/sxy_danxibao2_tls_connect_proxy_fixed.py   h3039@sxycloud1.top:/home/h3039/.local/libexec/sxy_danxibao2_tls_connect_proxy_fixed_staged.py
remote_patch="/tmp/sxy_proxy_patch_${GITHUB_RUN_ID}.sh"
sshpass -e scp -P 20111 -o StrictHostKeyChecking=yes   scripts/sxy_danxibao2_proxy_patch_deploy.sh   "h3039@sxycloud1.top:$remote_patch"

echo REPAIR_STAGE_APPLY
sshpass -e ssh -p 20111 -o StrictHostKeyChecking=yes -o ConnectTimeout=30 h3039@sxycloud1.top   "script='$remote_patch'; trap 'rm -f \"\$script\"' EXIT; bash \"\$script\""

echo REPAIR_STAGE_RESUME
sshpass -e ssh -p 20111 -o StrictHostKeyChecking=yes -o ConnectTimeout=30 h3039@sxycloud1.top 'bash -s' <<'REMOTE'
set -euo pipefail
unit=sxy-macaque-lung-convert-20261011
systemctl --user reset-failed "$unit" 2>/dev/null || true
systemctl --user restart "$unit"
sleep 5
systemctl --user show "$unit" -p ActiveState -p SubState -p Result -p ExecMainStatus --no-pager
echo MACAQUE_CONVERSION_RESUMED
REMOTE

unset SSHPASS SXY_PSWD
