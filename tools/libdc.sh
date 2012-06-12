#!/usr/bin/bash
#
# This is a library for the DC functions.
#

# Important! This is just a place-holder until we rewrite in node.
#

source /lib/sdc/config.sh
load_sdc_config

CURL_OPTS="-m 10 -sS -i"

# CNAPI!
CNAPI_IP=$(echo "${CONFIG_cnapi_admin_ips}" | cut -d ',' -f1)
if [[ -n ${CONFIG_cnapi_http_admin_user}
    && -n ${CONFIG_cnapi_http_admin_pw} ]]; then

    CNAPI_CREDENTIALS="${CONFIG_cnapi_http_admin_user}:${CONFIG_cnapi_http_admin_pw}"
fi
if [[ -n ${CNAPI_IP} ]]; then
    CNAPI_URL="http://${CNAPI_IP}"
fi

# VMAPI!
VMAPI_IP=$(echo "${CONFIG_vmapi_admin_ips}" | cut -d ',' -f1)
if [[ -n ${CONFIG_vmapi_http_admin_user}
    && -n ${CONFIG_vmapi_http_admin_pw} ]]; then

    VMAPI_CREDENTIALS="${CONFIG_vmapi_http_admin_user}:${CONFIG_vmapi_http_admin_pw}"
fi
if [[ -n ${VMAPI_IP} ]]; then
    VMAPI_URL="http://${VMAPI_IP}"
fi

# NAPI!
NAPI_URL=${CONFIG_napi_client_url}

if [[ -n ${CONFIG_napi_http_admin_user}
    && -n ${CONFIG_napi_http_admin_pw} ]]; then

    NAPI_CREDENTIALS="${CONFIG_napi_http_admin_user}:${CONFIG_napi_http_admin_pw}"
fi

# WORKFLOW!
WORKFLOW_IP=$(echo "${CONFIG_workflow_admin_ips}" | cut -d ',' -f1)
if [[ -n ${CONFIG_workflow_http_admin_user}
    && -n ${CONFIG_workflow_http_admin_pw} ]]; then

    WORKFLOW_CREDENTIALS="${CONFIG_workflow_http_admin_user}:${CONFIG_workflow_http_admin_pw}"
fi
if [[ -n ${WORKFLOW_IP} ]]; then
    WORKFLOW_URL="http://${WORKFLOW_IP}"
fi

fatal()
{
    echo "$@" >&2
    exit 1
}

cnapi()
{
    path=$1
    shift
    (curl ${CURL_OPTS} -u "${CNAPI_CREDENTIALS}" --url "${CNAPI_URL}${path}" \
        "$@") || return $?
    echo ""  # sometimes the result is not terminated with a newline
    return 0
}

napi()
{
    path=$1
    shift
    (curl ${CURL_OPTS} -u "${NAPI_CREDENTIALS}" --url "${NAPI_URL}${path}" \
        "$@") || return $?
    echo ""  # sometimes the result is not terminated with a newline
    return 0
}

workflow()
{
    path=$1
    shift
    (curl ${CURL_OPTS} -u "${WORKFLOW_CREDENTIALS}" --url \
        "${WORKFLOW_URL}${path}" "$@") || return $?
    echo ""  # sometimes the result is not terminated with a newline
    return 0
}

vmapi()
{
    path=$1
    shift
    curl ${CURL_OPTS} -u "${VMAPI_CREDENTIALS}" --url "${VMAPI_URL}${path}" \
        "$@" || return $?
    echo ""  # sometimes the result is not terminated with a newline
    return 0
}

# filename passed must have a 'Job-Location: ' header in it.
watch_job()
{
    local filename=$1

    # This may in fact be the hackiest possible way I could think up to do this
    rm -f /tmp/job_status.$$.old
    touch /tmp/job_status.$$.old
    local prev_execution=
    local chain_results=
    local execution=
    local job_status=
    local loop=0

    local job=$(json -H job_uuid < ${filename})
    if [[ -z ${job} ]]; then
        echo "+ FAILED! Result has no Job-Location: header. See ${filename}." >&2
        return 2
    fi

    echo "+ Job is /jobs/${job}"

    while [[ ${execution} != 'succeeded' && ${execution} != "failed" && ${loop} -lt 120 ]]; do
        job_status=$(workflow /jobs/${job} | json -H)
        echo "${job_status}" | json chain_results | json -a result > /tmp/job_status.$$.new
        diff -u /tmp/job_status.$$.old /tmp/job_status.$$.new | grep -v "No differences encountered" | grep "^+[^+]" | sed -e "s/^+/+ /"
        mv /tmp/job_status.$$.new /tmp/job_status.$$.old
        execution=$(echo "${job_status}" | json execution)
        if [[ ${execution} != ${prev_execution} ]]; then
            echo "+ Job status changed to: ${execution}"
            prev_execution=${execution}
        fi
        sleep 0.5
    done
    if [[ ${execution} == "succeeded" ]]; then
        echo "+ Success!"
        return 0
    else
        echo "+ FAILED! (details in /jobs/${job})" >&2
        return 1
    fi
}

provision_zone_from_payload()
{
    local tmpfile=$1
    local verbose="$2"

    vmapi /vms -X POST -H "Content-Type: application/json" --data-binary @${tmpfile} >/tmp/provision.$$ 2>&1
    return_code=$?
    if [[ ${return_code} != 0 ]]; then
        echo "VMAPI FAILED with:" >&2
        cat /tmp/provision.$$ >&2
        return ${return_code}
    fi
    provisioned_uuid=$(json -H vm_uuid < /tmp/provision.$$)
    if [[ -z ${provisioned_uuid} ]]; then
        if [[ -n $verbose ]]; then
            echo "+ FAILED: Unable to get uuid for new ${zrole} VM (see /tmp/provision.$$)."
            cat /tmp/provision.$$ | json -H
            exit 1
        else
            fatal "+ FAILED: Unable to get uuid for new ${zrole} VM (see /tmp/provision.$$)."
        fi
    fi

    echo "+ Sent provision to VMAPI for ${provisioned_uuid}"
    watch_job /tmp/provision.$$

    return $?
}