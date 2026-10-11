#!/usr/bin/env bash
set -euo pipefail
set +x

test -n "${SXY_PSWD:-}"
sudo apt-get update -qq
sudo apt-get install -y -qq sshpass >/dev/null
install -d -m 700 "$HOME/.ssh"
ssh-keyscan -p 20111 sxycloud1.top > "$HOME/.ssh/known_hosts" 2>/dev/null
chmod 600 "$HOME/.ssh/known_hosts"
export SSHPASS="$SXY_PSWD"

target=/home/h3039/PROJECTS/zhumiao/.sxy_macaca_lung_work
sshpass -e ssh -p 20111 -o StrictHostKeyChecking=yes -o ConnectTimeout=30 h3039@sxycloud1.top "mkdir -p '$target'"
sshpass -e scp -P 20111 -o StrictHostKeyChecking=yes   scripts/sxy_macaca_lung_pipeline.py   scripts/sxy_macaca_lung_validate.R   "h3039@sxycloud1.top:$target/"

sshpass -e ssh -p 20111 -o StrictHostKeyChecking=yes -o ConnectTimeout=30 h3039@sxycloud1.top 'bash -s' <<'REMOTE'
set -euo pipefail
set +x
target="$HOME/PROJECTS/zhumiao/.sxy_macaca_lung_work"
py="$target/sxy_macaca_lung_pipeline.py"
rv="$target/sxy_macaca_lung_validate.R"
python3 -m py_compile "$py"
Rscript --vanilla -e 'invisible(parse(file="~/PROJECTS/zhumiao/.sxy_macaca_lung_work/sxy_macaca_lung_validate.R"));cat("R_VALIDATOR_PARSE_PASS\n")'
test -s "$HOME/reference/Macaca_fascicularis_5_0_Ensembl100/reference.json"
test -s "$HOME/reference/Macaca_fascicularis_5_0_Ensembl100/fasta/genome.fa"
mountpoint -q "$HOME/PROJECTS/zhumiao/danxibao2"
echo REFERENCE_AND_MOUNT_PASS

old=sxy-macaque-lung-matrix-20261010
systemctl --user stop "$old" 2>/dev/null || true
systemctl --user reset-failed "$old" 2>/dev/null || true

unit=sxy-macaque-lung-convert-20261011
if systemctl --user show "$unit" -p LoadState --value 2>/dev/null | grep -qx loaded; then
  systemctl --user restart "$unit"
  echo CONVERSION_SERVICE_RESTARTED="$unit"
else
  systemd-run --user --unit="$unit" /usr/bin/python3 "$py"
  echo CONVERSION_SERVICE_STARTED="$unit"
fi
sleep 5
systemctl --user show "$unit" -p ActiveState -p SubState -p Result -p ExecMainStatus --no-pager
out="$HOME/PROJECTS/zhumiao/danxibao2/数据清理整理/刘光慧食蟹猴肺"
done_count=0
if [ -d "$out" ]; then
  done_count="$(find "$out" -mindepth 2 -maxdepth 2 -name VALIDATION_PASS.txt -type f 2>/dev/null | wc -l)"
fi
echo FULLY_VALIDATED_SAMPLES="$done_count"/15
journalctl --user -u "$unit" --no-pager --output=cat -n 40 2>/dev/null   | grep -E 'MOUNT_COPY|SOURCE_OK|RUN |SAMPLE_COMPLETE|SAMPLE_FAILED|RESUME_EXISTING|ALL_15|WAIT_REFERENCE'   | tail -n 30 || true
REMOTE

unset SSHPASS SXY_PSWD
