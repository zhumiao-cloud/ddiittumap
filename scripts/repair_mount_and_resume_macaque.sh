#!/usr/bin/env bash
set -euo pipefail
set +x
trap 'rc=$?; echo MOUNT_REPAIR_FAILED_LINE=$LINENO RC=$rc; exit $rc' ERR

test -n "${SXY_PSWD:-}"
sudo apt-get update -qq
sudo apt-get install -y -qq sshpass >/dev/null
install -d -m 700 "$HOME/.ssh"
ssh-keyscan -T 15 -p 20111 sxycloud1.top > "$HOME/.ssh/known_hosts" 2>/dev/null
chmod 600 "$HOME/.ssh/known_hosts"
export SSHPASS="$SXY_PSWD"

sshpass -e ssh -p 20111 -o StrictHostKeyChecking=yes -o ConnectTimeout=30 h3039@sxycloud1.top 'bash -s' <<'REMOTE'
set -euo pipefail
set +x
mnt="$HOME/PROJECTS/zhumiao/danxibao2"
mount_unit=rclone-danxibao2-webdav.service
proxy_unit=rclone-danxibao2-connect-proxy.service
conv_unit=sxy-macaque-lung-convert-20261011

systemctl --user is-active --quiet "$proxy_unit"
echo PROXY_ACTIVE=YES

echo MOUNT_REPAIR_STOP
systemctl --user stop "$mount_unit" 2>/dev/null || true
fusermount3 -uz "$mnt" 2>/dev/null || true
sleep 2
systemctl --user restart "$mount_unit"

ok=0
for i in $(seq 1 20); do
  if mountpoint -q "$mnt" && timeout 20 dd if="$mnt/刘光慧食蟹猴肺/CRR130924/CRR130924_r2.fq.gz" of=/dev/null bs=1M count=4 status=none 2>/tmp/sxy-mount-probe.err; then
    ok=1
    break
  fi
  sleep 3
done
if [ "$ok" -ne 1 ]; then
  echo MOUNT_REPAIR_PROBE=FAIL
  cat /tmp/sxy-mount-probe.err 2>/dev/null || true
  exit 31
fi
echo MOUNT_REPAIR_PROBE=PASS

for spec in   "CRR130928/CRR130928_f1.fq.gz"   "CRR130932/CRR130932_f1.fq.gz"   "CRR130936/CRR130936_f1.fq.gz"   "CRR130940/CRR130940_f1.fq.gz"; do
  timeout 30 dd if="$mnt/刘光慧食蟹猴肺/$spec" of=/dev/null bs=1M count=4 status=none
  echo "MOUNT_FASTQ_${spec%%/*}=PASS"
done

systemctl --user reset-failed "$conv_unit" 2>/dev/null || true
systemctl --user restart "$conv_unit"
sleep 8
systemctl --user show "$mount_unit" -p ActiveState -p SubState -p Result --no-pager
systemctl --user show "$conv_unit" -p ActiveState -p SubState -p Result -p ExecMainStatus --no-pager
echo MACAQUE_CONVERSION_RESTARTED_AFTER_REMOUNT
REMOTE

unset SSHPASS SXY_PSWD
