#!/usr/bin/env bash
set -euo pipefail
set +x
trap 'rc=$?; echo STATUS_FAILED_LINE=$LINENO RC=$rc; exit $rc' ERR
test -n "${SXY_PSWD:-}"
echo STATUS_STAGE_INSTALL
sudo apt-get update -qq
sudo apt-get install -y -qq sshpass >/dev/null
install -d -m 700 "$HOME/.ssh"
echo STATUS_STAGE_HOSTKEY
ssh-keyscan -T 15 -p 20111 sxycloud1.top > "$HOME/.ssh/known_hosts" 2>/dev/null
chmod 600 "$HOME/.ssh/known_hosts"
export SSHPASS="$SXY_PSWD"
echo STATUS_STAGE_REMOTE
sshpass -e ssh -p 20111 -o StrictHostKeyChecking=yes -o ConnectTimeout=30 h3039@sxycloud1.top 'bash -s' <<'REMOTE'
set -u
unit=sxy-macaque-lung-convert-20261011
old=sxy-macaque-lung-matrix-20261010
echo "NEW_UNIT"
systemctl --user show "$unit" -p LoadState -p ActiveState -p SubState -p Result -p ExecMainStatus --no-pager 2>/dev/null || true
echo "OLD_UNIT"
systemctl --user show "$old" -p LoadState -p ActiveState -p SubState -p Result -p ExecMainStatus --no-pager 2>/dev/null || true
if test -s "$HOME/reference/Macaca_fascicularis_5_0_Ensembl100/reference.json"; then echo REFERENCE_PRESENT=YES; else echo REFERENCE_PRESENT=NO; fi
if mountpoint -q "$HOME/PROJECTS/zhumiao/danxibao2"; then echo DANXIBAO2_MOUNT=YES; else echo DANXIBAO2_MOUNT=NO; fi
out="$HOME/PROJECTS/zhumiao/danxibao2/数据清理整理/刘光慧食蟹猴肺"
done_count=0
if [ -d "$out" ]; then done_count="$(find "$out" -mindepth 2 -maxdepth 2 -name VALIDATION_PASS.txt -type f 2>/dev/null | wc -l)"; fi
echo FULLY_VALIDATED_SAMPLES="$done_count"/15
du -sh "$HOME/PROJECTS/zhumiao/.sxy_macaca_lung_work/local_fastqs" 2>/dev/null || true
echo RCLONE_MOUNT_ERRORS
log="$HOME/.cache/rclone/danxibao2-webdav-mount.log"
if [ -f "$log" ]; then
  tail -n 240 "$log"    | sed -E 's#https://[^ /"[:space:]]+#https://[redacted-host]#g; s#[?][^"[:space:]]+#[?][redacted]#g'    | grep -Ei 'ERROR|failed|forbidden|403|timeout|reset|input/output'    | tail -n 80 || true
fi
echo RCLONE_ERROR_HOSTS
if [ -f "$log" ]; then
  tail -n 400 "$log"    | grep -Ei 'Forbidden|403|ReadFileHandle.Read error|failed'    | grep -Eo 'https://[^/"[:space:]]+'    | sed -E 's#^https://##'    | sort -u || true
fi
echo PROXY_LISTENER
ss -ltn 2>/dev/null | grep '127.0.0.1:19324' || true
journalctl --user -u "$unit" --no-pager --output=cat -n 80 2>/dev/null  | grep -E 'MOUNT_COPY|SOURCE_OK|RUN |SAMPLE_COMPLETE|SAMPLE_FAILED|RESUME_EXISTING|ALL_15|WAIT_REFERENCE'  | tail -n 60 || true
REMOTE
unset SSHPASS SXY_PSWD
