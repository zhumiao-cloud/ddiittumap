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
journalctl --user -u "$unit" --no-pager --output=cat -n 80 2>/dev/null  | grep -E 'MOUNT_COPY|SOURCE_OK|RUN |SAMPLE_COMPLETE|SAMPLE_FAILED|RESUME_EXISTING|ALL_15|WAIT_REFERENCE'  | tail -n 60 || true
REMOTE
unset SSHPASS SXY_PSWD
