#!/bin/bash
# -------------------------------------------------------------------------------------
# Copyright (c) 2022 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
#
# WSO2 Inc. licenses this file to you under the Apache License,
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
# Prepares an isolated deployment directory for a single test group by cloning the
# base infrastructure combination's parameter file and giving the group its own
# CloudFormation stack name. This allows each test group to run against a separate
# deployment instead of sharing one stack.
#
# IMPORTANT: Only the resulting deployment directory name is written to stdout so the
# caller (Jenkins pipeline) can capture it. Keep all diagnostic output off stdout.
# --------------------------------------------------------------------------------------

baseDeploymentName=$1
testGroup=$2

currentScript=$(dirname $(realpath "$0"))
source ${currentScript}/common-functions.sh

baseDeploymentDir="${WORKSPACE}/deployment/${baseDeploymentName}"
baseParameterFile="${baseDeploymentDir}/parameters.json"

function generateRandomString(){
    tr -dc A-Za-z0-9 </dev/urandom | head -c 8 ; echo ''
}

function removeSpecialCharacters(){
    local stringValue=$1
    echo "${stringValue}" | sed 's|[_.,/ ]||g'
}

sanitizedGroup=$(removeSpecialCharacters "${testGroup}")
groupDeploymentName="${baseDeploymentName}-${sanitizedGroup}"
groupDeploymentDir="${WORKSPACE}/deployment/${groupDeploymentName}"
groupParameterFile="${groupDeploymentDir}/parameters.json"

# An isolated directory + parameter file is created per test group
mkdir -p "${groupDeploymentDir}"
cp "${baseParameterFile}" "${groupParameterFile}"

# Give this group its own stack name and unique identifier so the deployments,
# log paths and teardown stay isolated from other groups in the same combination.
uniqueIdentifier=$(generateRandomString)
baseStackName=$(extractParameters "StackName" "${groupParameterFile}")
newStackName="${baseStackName}-${sanitizedGroup}-${uniqueIdentifier}"

./scripts/write-parameter-file.sh "StackName" "${newStackName}" "${groupParameterFile}" 1>/dev/null
./scripts/write-parameter-file.sh "UniqueIdentifier" "${uniqueIdentifier}" "${groupParameterFile}" 1>/dev/null

# Only the deployment directory name goes to stdout for the caller to capture.
echo "${groupDeploymentName}"
