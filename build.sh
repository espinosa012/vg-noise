#!/bin/sh
# build.sh - compila libvnoise y genera el módulo vnoise.lua listo para usar
#
# Uso:
#   ./build.sh                # build con -march=native (default)
#   ./build.sh portable       # build portable sin -march=native
#   ./build.sh clean          # limpia artefactos
#
# Salida: dist/ con vnoise.lua + libvnoise.<ext> (dylib/so/dll)

set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"

case "${1:-build}" in
  clean)
    make -C "$ROOT" clean
    rm -rf "$DIST"
    echo "limpiado"
    exit 0
    ;;
  portable)
    NATIVE=0
    ;;
  build|"")
    NATIVE=1
    ;;
  *)
    echo "uso: $0 [build|portable|clean]"
    exit 1
    ;;
esac

# 1. Compilar la librería
echo "== compilando libvnoise =="
if [ "$NATIVE" = "0" ]; then
  make -C "$ROOT" NATIVE=0
else
  make -C "$ROOT"
fi

# 2. Detectar la extensión producida
case "$(uname -s)" in
  Darwin)        EXT="dylib" ;;
  Linux)         EXT="so"    ;;
  MINGW*|MSYS*)  EXT="dll"   ;;
  *) echo "plataforma no soportada: $(uname -s)"; exit 1 ;;
esac

LIB="$ROOT/libvnoise.$EXT"
LUA="$ROOT/lua/vnoise.lua"

if [ ! -f "$LIB" ]; then
  echo "error: no se generó $LIB"
  exit 1
fi
if [ ! -f "$LUA" ]; then
  echo "error: no se encontró $LUA"
  exit 1
fi

# 3. Empaquetar en dist/
mkdir -p "$DIST"
cp "$LIB" "$DIST/"
cp "$LUA" "$DIST/vnoise.lua"

echo
echo "== build OK =="
echo "artefactos en dist/:"
ls -la "$DIST"
echo
echo "copia dist/vnoise.lua y dist/libvnoise.$EXT a tu proyecto love2d"
echo "y al inicio de main.lua añade:"
echo "  package.cpath = package.cpath .. \";./?.${EXT};./libvnoise.${EXT}\""
echo "  package.path  = package.path  .. \";./?.lua\""
echo "  local vnoise = require(\"vnoise\")"