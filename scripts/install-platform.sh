#!/bin/bash
#
# Copyright (c) 2011 Joyent Inc., All rights reserved.
#

set -o errexit
set -o pipefail
#set -o xtrace

input=$1
if [[ -z ${input} ]]; then
    echo "Usage: $0 <platform URI>"
    echo "(URI can be file:///, http://, or anything curl supports)"
    exit 1
fi

mounted="false"
usbmnt="/mnt/$(svcprop -p 'joyentfs/usb_mountpoint' svc:/system/filesystem/smartdc:default)"
usbcpy="$(svcprop -p 'joyentfs/usb_copy_path' svc:/system/filesystem/smartdc:default)"

. /lib/sdc/config.sh
load_sdc_config

if [[ -z $(mount | grep ^${usbmnt}) ]]; then
    echo "==> Mounting USB key"
    /usbkey/scripts/mount-usb.sh
    mounted="true"
fi

# this should result in something like 20110318T170209Z
version=$(basename "${input}" | sed -e "s/.*\-\(2.*Z\)\.tgz/\1/")

if [[ -d ${usbmnt}/os/${version} ]]; then
    echo "FATAL: ${usbmnt}/os/${version} already exists."
    exit 1
fi

echo "==> Unpacking ${version} to ${usbmnt}/os"
curl --progress -k ${input} \
    | (mkdir -p ${usbmnt}/os/${version} \
    && cd ${usbmnt}/os/${version} \
    && gunzip | tar -xf - 2>/tmp/install_platform.log \
    && mv platform-* platform
)

if [[ -f ${usbmnt}/os/${version}/platform/root.password ]]; then
     mv -f ${usbmnt}/os/${version}/platform/root.password \
         ${usbmnt}/private/root.password.${version}
fi

echo "==> Copying ${version} to ${usbcpy}/os"
mkdir -p ${usbcpy}/os
(cd ${usbmnt}/os && rsync -a ${version}/ ${usbcpy}/os/${version})

if [[ ${mounted} == "true" ]]; then
    echo "==> Unmounting USB Key"
    umount /mnt/usbkey
fi

echo "==> Adding to list of available platforms"

curr_list=$(curl -s -f -u "${CONFIG_mapi_http_admin_user}:${CONFIG_mapi_http_admin_pw}" \
    --url http://${CONFIG_mapi_admin_ip}/admin/platform_images 2>/dev/null || /bin/true)
if [[ -n ${curr_list} ]]; then
    elements=$(echo "${curr_list}" | json length)
    found="false"
    idx=0
    while [[ ${found} == "false" && ${idx} -lt ${elements} ]]; do
        name=$(echo "${curr_list}" | json ${idx}.name)
        if [[ -n ${version} && ${name} == ${version} ]]; then
            found="true"
        fi
        idx=$(($idx + 1))
    done

    if [[ -n ${version} && ${found} != "true" ]]; then
        if ! curl -s -f \
            -X POST \
            -u "${CONFIG_mapi_http_admin_user}:${CONFIG_mapi_http_admin_pw}" \
            --url http://${CONFIG_mapi_admin_ip}/admin/platform_images \
            -H "Accept: application/json" \
            -d name=${version} >/dev/null 2>&1; then

            echo "==> FAILED to add to list of platforms, you'll need to update manually"
        else
            echo "==> Added ${version} to MAPI's list"
        fi
    fi

else
    echo "FAILED to get current list of platforms, can't update."
fi

echo "==> Done!"

exit 0
