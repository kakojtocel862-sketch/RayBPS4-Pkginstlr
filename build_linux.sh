#!/bin/bash
# Builds the RayBPS4 Installer package on Linux (clang + lld + OpenOrbis toolchain).
# Usage: OO_PS4_TOOLCHAIN=/path/to/toolchain bash build_linux.sh
set -euo pipefail

: "${OO_PS4_TOOLCHAIN:?OO_PS4_TOOLCHAIN is not set}"
TC="$OO_PS4_TOOLCHAIN"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
chmod +x "$TC"/bin/linux/* 2>/dev/null || true

TITLE="RayBPS4 Installer"
VERSION="01.01"
TITLE_ID="KPBR01111"
CONTENT_ID="IV0000-KPBR01111_00-AAAAAAAAAAAAAAAA"
LIBS="-lc -lkernel -lc++ -lSceUserService -lSceSystemService -lSceNet -lSceHttp -lSceBgft -lSceAppInstUtil -lSceSsl -lSceSysmodule -lSceNetCtl -lSceJson -lSceNpUtility -lSceNpCommon"

OUT="$ROOT/build"
rm -rf "$OUT" eboot.bin pkg.gp4 sce_sys/param.sfo ./*.pkg
mkdir -p "$OUT/obj"

echo "== Generating the web page header"
python3 tools/gen_ui_header.py ui/index.html RPI/ui_html.h

echo "== Compiling"
cd RPI
for f in *.c; do
  echo "   $f"
  clang --target=x86_64-pc-freebsd12-elf -fPIC -funwind-tables \
    -I"$TC/include" -I"$TC/include/c++/v1" \
    -c -o "$OUT/obj/${f%.c}.o" "$f"
done
cd "$ROOT"

echo "== Linking"
ld.lld -m elf_x86_64 -pie --script "$TC/link.x" --eh-frame-hdr \
  -o "$OUT/RPI.elf" "-L$TC/lib" $LIBS "$TC/lib/crt1.o" "$OUT"/obj/*.o

echo "== Creating eboot.bin"
"$TC/bin/linux/create-fself" -in="$OUT/RPI.elf" -out="$OUT/RPI.oelf" --eboot "eboot.bin" --paid 0x3800000000000011

echo "== Creating param.sfo"
PT="$TC/bin/linux/PkgTool.Core"
"$PT" sfo_new sce_sys/param.sfo
"$PT" sfo_setentry sce_sys/param.sfo APP_TYPE --type Integer --maxsize 4 --value 1
"$PT" sfo_setentry sce_sys/param.sfo APP_VER --type Utf8 --maxsize 8 --value "$VERSION"
"$PT" sfo_setentry sce_sys/param.sfo ATTRIBUTE --type Integer --maxsize 4 --value 0
"$PT" sfo_setentry sce_sys/param.sfo CATEGORY --type Utf8 --maxsize 4 --value "gd"
"$PT" sfo_setentry sce_sys/param.sfo CONTENT_ID --type Utf8 --maxsize 48 --value "$CONTENT_ID"
"$PT" sfo_setentry sce_sys/param.sfo DOWNLOAD_DATA_SIZE --type Integer --maxsize 4 --value 0
"$PT" sfo_setentry sce_sys/param.sfo SYSTEM_VER --type Integer --maxsize 4 --value 0
"$PT" sfo_setentry sce_sys/param.sfo TITLE --type Utf8 --maxsize 128 --value "$TITLE"
"$PT" sfo_setentry sce_sys/param.sfo TITLE_ID --type Utf8 --maxsize 12 --value "$TITLE_ID"
"$PT" sfo_setentry sce_sys/param.sfo VERSION --type Utf8 --maxsize 8 --value "$VERSION"

echo "== Creating the package"
FILES="eboot.bin sce_sys/about/right.sprx sce_sys/param.sfo sce_sys/icon0.png"
for m in sce_module/*; do
  case "$m" in *.prx) FILES="$FILES $m";; esac
done
"$TC/bin/linux/create-gp4" -out pkg.gp4 --content-id="$CONTENT_ID" --files "$FILES"
"$PT" pkg_build pkg.gp4 .

echo "== Done:"
ls -l ./*.pkg
