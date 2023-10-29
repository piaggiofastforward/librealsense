#!/bin/bash
# file: rs_ipu6_d457_bind.sh
# This script used for binding media links of v4l2 subdevice entities
# The configuration we had is DS5 mux and IPU6 entities.
# _______  _______  _______  _______  _________
# |depth|->| mux |->|CSI-2|->|BESOC|->|capture|
# |_____|  |_____|  |_____|  |_____|  |_______|
#
# Full graph can be viewed on http://magjac.com/graphviz-visual-editor/
# media graph links can be generated by running 'media-ctl --print-dot'
#
# Dependency: v4l-utils
v4l2_util=$(which v4l2-ctl)
media_util=$(which media-ctl)
if [ -z ${v4l2_util} ]; then
  echo "v4l2-ctl not found, install with: sudo apt install v4l-utils"
  exit 1
fi
# enable metadata capture nodes for default
metadata_enabled=1
while [[ $# -gt 0 ]]; do
  case $1 in
    -q|--quiet)
      quiet=1
      shift
    ;;
    -m|--mux)
      shift
      mux_param=$1
      shift
    ;;
    -n|--no-metadata)
      metadata_enabled=0
      shift
    ;;
    -h|--help)
      echo "-q -m -n -h"
    ;;
    *)
      quiet=0
      shift
    ;;
    esac
done

# mapping for DS5 mux entity to IPU6 BE SOC entity matching.
declare -A media_mux_capture_link=( [a]='' [b]='1 ' [c]='2 ' [d]='3 ' [e]='' [f]='1 ' [g]='2 ' [h]='3 ')
# mapping for DS5 mux entity to IPU6 CSI-2 entity matching.
declare -A media_mux_csi2_link=( [a]=0 [b]=1 [c]=2 [d]=3 [e]=0 [f]=1 [g]=2 [h]=3)

# all available DS5 muxes, each one represent physically connected camera.
# muxes a, b, c, d usually single link cameras
# muxes e, f, g, h is aggregated link cameras, 'a' coupled to 'e'

mux_list=${mux_param:-'a b c d e f g h'}
# Find media device.
# For case with usb camera plugged in during the boot,
# usb media controller will occupy index 0
mdev=$(${v4l2_util} --list-devices | grep -A1 ipu6 | grep media)
[[ -z "${mdev}" ]] && exit 0

media_ctl_cmd="${media_util} -d ${mdev}"
#media-ctl -r # <- this can be used to clean-up all bindings from media controller
# cache media-ctl output
dot=$($media_ctl_cmd --print-dot)

# DS5 MUX. Can be {a, b, c, d} + Aggregated {e, f, g, h}.
for mux in $mux_list; do
  is_mux=$(echo "${dot}" | grep "DS5 mux ${mux}")
  # skip for non-existing muxes
  [[ -z $is_mux ]] && continue;

  [[ $quiet -eq 0 ]] && echo -n "Bind DS5 mux ${mux} .. "

  csi2_be_soc="CSI2 BE SOC ${media_mux_csi2_link[${mux}]}"

  csi2="CSI-2 ${media_mux_csi2_link[${mux}]}"
  # capture pad
  be_soc_cap="BE SOC ${media_mux_capture_link[${mux}]}capture"

  cap_pad=0
  # bind (enable) link CSI-2 pad 1 to BE-SOC pad 0
  $media_ctl_cmd -v -l "\"Intel IPU6 ${csi2}\":1 -> \"Intel IPU6 ${csi2_be_soc}\":0[1]" 1>/dev/null
  # bind (enable) link DS5 mux pad 0 to CSI-2 pad 0
  $media_ctl_cmd -v -l "\"DS5 mux ${mux}\":0 -> \"Intel IPU6 ${csi2}\":0[1]" 1>/dev/null

  # for DS5 aggregated mux (above d) - use BE-SOC capture pads with offset 6
  # this offset used as capture sensor set - dept+md,rgb+md,ir,imu = 6
  cap_pad=0
  if [ "${mux}" \> "d" ]; then
    cap_pad=6
  fi

  # DEPTH video streaming node
  $media_ctl_cmd -v -l "\"Intel IPU6 ${csi2_be_soc}\":$((${cap_pad}+1)) -> \"Intel IPU6 ${be_soc_cap} $((${cap_pad}+0))\":0[5]" 1>/dev/null
  # DEPTH metadata node
  if [[ $metadata_enabled -eq 1 ]]; then
    $media_ctl_cmd -v -l "\"Intel IPU6 ${csi2_be_soc}\":$((${cap_pad}+2)) -> \"Intel IPU6 ${be_soc_cap} $((${cap_pad}+1))\":0[5]" 1>/dev/null
  fi

  # RGB link video streaming node
  $media_ctl_cmd -v -l "\"Intel IPU6 ${csi2_be_soc}\":$((${cap_pad}+3)) -> \"Intel IPU6 ${be_soc_cap} $((${cap_pad}+2))\":0[5]" 1>/dev/null
  # RGB metadata node
  if [[ $metadata_enabled -eq 1 ]]; then
    $media_ctl_cmd -v -l "\"Intel IPU6 ${csi2_be_soc}\":$((${cap_pad}+4)) -> \"Intel IPU6 ${be_soc_cap} $((${cap_pad}+3))\":0[5]" 1>/dev/null
  fi

  # IR link video streaming node
  $media_ctl_cmd -v -l "\"Intel IPU6 ${csi2_be_soc}\":$((${cap_pad}+5)) -> \"Intel IPU6 ${be_soc_cap} $((${cap_pad}+4))\":0[5]" 1>/dev/null

  # IMU link streaming node
  $media_ctl_cmd -v -l "\"Intel IPU6 ${csi2_be_soc}\":$((${cap_pad}+6)) -> \"Intel IPU6 ${be_soc_cap} $((${cap_pad}+5))\":0[5]" 1>/dev/null

done