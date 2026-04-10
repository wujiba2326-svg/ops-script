#!/bin/bash

PPP_OPTIONS="/etc/ppp/options"

open-dx() {
  echo "plugin L2TP.ppp
l2tpnoipsec" | sudo tee "$PPP_OPTIONS" > /dev/null
  sudo sysctl net.link.generic.system.hwcksum_tx=0
  sudo sysctl net.link.generic.system.hwcksum_rx=0
  echo "[open-dx] 完成"
}

off-dx() {
  echo "# plugin L2TP.ppp
# l2tpnoipsec" | sudo tee "$PPP_OPTIONS" > /dev/null
  sudo sysctl net.link.generic.system.hwcksum_tx=1
  sudo sysctl net.link.generic.system.hwcksum_rx=1
  echo "[off-dx] 完成"
}

case "${1:-}" in
  open-dx) open-dx ;;
  off-dx)  off-dx  ;;
  *)
    echo "用法: $0 {open-dx|off-dx}"
    exit 1
    ;;
esac
