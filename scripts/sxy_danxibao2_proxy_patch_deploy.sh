#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077
OLD="$HOME/.local/libexec/danxibao2_tls_connect_proxy.py"
STAGED="$HOME/.local/libexec/sxy_danxibao2_tls_connect_proxy_fixed_staged.py"
SERVICE="rclone-danxibao2-connect-proxy.service"
BACKUP="${OLD}.bak.sxy_20261010_$$"
TMP="$(mktemp -d)"
REMOTE="danxibao2_webdav:数据清理整理/.sxy_proxy_verified_20261010_$$.bin"
rollback=1
uploaded=0
export HTTPS_PROXY=http://127.0.0.1:19324
export https_proxy=http://127.0.0.1:19324
export NO_PROXY=localhost,127.0.0.1
export no_proxy=localhost,127.0.0.1
cleanup() {
  local rc=$?
  set +e
  if [ "$uploaded" -eq 1 ]; then
    rclone deletefile "$REMOTE" >/dev/null 2>&1
  fi
  if [ "$rollback" -eq 1 ] && [ -s "$BACKUP" ]; then
    cp -p "$BACKUP" "$OLD"
    systemctl --user restart "$SERVICE"
    echo "CONNECT_PROXY_ROLLBACK=ATTEMPTED"
  fi
  rm -rf "$TMP"
  exit "$rc"
}
trap cleanup EXIT

test -s "$OLD"
test -s "$STAGED"
python3 -m py_compile "$STAGED"
python3 - "$STAGED" <<'PY'
import ast,sys
t=ast.parse(open(sys.argv[1]).read())
assigns={name.id:node.value for node in t.body if isinstance(node,ast.Assign) for name in node.targets if isinstance(name,ast.Name)}
targets=ast.literal_eval(assigns["TARGETS"])
expected={
 b"pan.evren.cn:443",
 b"qd01-httpdown.guangyacdn.com:443",
 b"qd02-httpdown.guangyacdn.com:443",
 b"sh01-httpdown.guangyacdn.com:443",
 b"sh02-httpdown.guangyacdn.com:443",
 b"ydfh01-httpdown.guangyacdn.cn:443",
 b"ydfh02-httpdown.guangyacdn.cn:443",
}
assert set(targets)==expected, (set(targets), expected)
assert targets[b"sh02-httpdown.guangyacdn.com:443"]==("218.91.170.219",)
assert targets[b"ydfh01-httpdown.guangyacdn.cn:443"]==("223.109.90.155",)
assert targets[b"ydfh02-httpdown.guangyacdn.cn:443"]==("223.109.91.146",)
assert ast.literal_eval(assigns["LISTEN"])==("127.0.0.1",19324)
print("PINNED_ALLOWLIST_VALIDATED")
PY

cp -p "$OLD" "$BACKUP"
install -m 700 "$STAGED" "$OLD"
systemctl --user restart "$SERVICE"
systemctl --user is-active --quiet "$SERVICE"
echo "PROXY_RESTART=PASS"

for run in CRR130924 CRR130928 CRR130932 CRR130936 CRR130940; do
  f="danxibao2_webdav:刘光慧食蟹猴肺/$run/${run}_f1.fq.gz"
  hdr="$TMP/${run}.header"
  err="$TMP/${run}.err"
  if ! timeout 75 rclone cat "$f" --head 4 >"$hdr" 2>"$err"; then
    echo "FASTQ_${run}_READ=FAIL"
    exit 41
  fi
  python3 - "$hdr" "$run" <<'PY'
import sys
data=open(sys.argv[1],"rb").read()
assert data==bytes.fromhex("1f8b0804"), (sys.argv[2],data.hex())
print("FASTQ_"+sys.argv[2]+"_GZIP_HEADER=PASS")
PY
done

head -c 131072 /dev/urandom > "$TMP/upload"
if ! timeout 60 rclone copyto "$TMP/upload" "$REMOTE" >"$TMP/upload.out" 2>"$TMP/upload.err"; then
  echo "WEBDAV_UPLOAD=FAIL"
  exit 42
fi
uploaded=1
echo "WEBDAV_UPLOAD=PASS"
if ! timeout 60 rclone copyto "$REMOTE" "$TMP/readback" >"$TMP/readback.out" 2>"$TMP/readback.err"; then
  echo "WEBDAV_READBACK=FAIL"
  python3 - "$TMP/readback.err" <<'PY'
import re,sys
s=open(sys.argv[1],errors="replace").read()
hosts=sorted(set(re.findall(r'https://([A-Za-z0-9.-]+)',s)))
print("READBACK_REDIRECT_HOSTS="+(",".join(hosts) if hosts else "NONE"))
classes=[]
for token in ("Forbidden","Bad Gateway","timeout","connection reset","no such host"):
    if token.lower() in s.lower(): classes.append(token.replace(" ","_").upper())
print("READBACK_ERROR_CLASS="+(",".join(classes) if classes else "OTHER"))
PY
  exit 43
fi
cmp "$TMP/upload" "$TMP/readback"
echo "WEBDAV_READBACK_BYTE_COMPARISON=PASS"
rollback=0
echo "SCOPED_PROXY_FIX_VERIFIED_AND_RETAINED=PASS"
