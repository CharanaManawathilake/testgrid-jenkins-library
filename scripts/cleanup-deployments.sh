#!/bin/bash
# -------------------------------------------------------------------------------------
# Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com) All Rights Reserved.
#
# WSO2 LLC. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
# --------------------------------------------------------------------------------------
#
# Best-effort teardown of every CloudFormation stack created by this build.
#
# During the normal flow stacks are deleted inside post-actions.sh as each test stage
# finishes. However, when a build is aborted/killed those scripts are interrupted before
# teardown runs, leaving stacks alive. This script is meant to be called from the
# pipeline's post{always} block: it scans every per-deployment parameter file on disk,
# and issues a delete for any stack still standing.
#
# The deletes are fire-and-forget (no wait): issuing delete-stack is enough for AWS to
# tear the stack down asynchronously, which keeps post-build cleanup fast even on abort.
# The scan is idempotent - stacks already deleted (or mid-deletion) are skipped, so it is
# safe to run after a successful build where teardown already happened.
# --------------------------------------------------------------------------------------

currentScript=$(dirname $(realpath "$0"))
source ${currentScript}/common-functions.sh

deploymentRoot="${WORKSPACE}/deployment"

if [ ! -d "${deploymentRoot}" ]; then
    log_info "No deployment directory found at ${deploymentRoot}. Nothing to clean up."
    exit 0
fi

log_info "Scanning ${deploymentRoot} for CloudFormation stacks to clean up..."

# Each combination / test group owns one parameters.json directly under its deployment
# directory. Restrict the scan to that depth so parameter files inside cloned test repos
# are not picked up.
while IFS= read -r -d '' parameterFile; do
    stackName=$(extractParameters "StackName" "${parameterFile}")
    region=$(extractParameters "Region" "${parameterFile}")

    if [[ -z "${stackName}" || "${stackName}" == "null" ]]; then
        log_info "No StackName in ${parameterFile}. Skipping."
        continue
    fi

    stackStatus=$(aws cloudformation describe-stacks --stack-name "${stackName}" --region "${region}" 2> /dev/null | jq -r '.Stacks[0].StackStatus')
    if [[ -z "${stackStatus}" || "${stackStatus}" == "null" ]]; then
        log_info "Stack ${stackName} not found (already deleted). Skipping."
        continue
    fi
    if [[ "${stackStatus}" == "DELETE_IN_PROGRESS" || "${stackStatus}" == "DELETE_COMPLETE" ]]; then
        log_info "Stack ${stackName} is already ${stackStatus}. Skipping."
        continue
    fi

    log_info "Deleting stack ${stackName} in region ${region} (current status: ${stackStatus})"
    aws cloudformation delete-stack --stack-name "${stackName}" --region "${region}"
    if [[ $? != 0 ]];
    then
        log_error "Failed to issue delete for stack ${stackName}"
    else
        log_info "Delete request issued for stack ${stackName}"
    fi
done < <(find "${deploymentRoot}" -mindepth 2 -maxdepth 2 -type f -name 'parameters.json' -print0)

log_info "Stack cleanup scan completed."
