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
# Orchestrates the test flow for a single deployment. A phase can be supplied so the
# pipeline can drive each part as its own step (small, fully-renderable logs):
#
#   clone       - clone the product test repo onto the slave
#   setup|update|provisiondb|test|collect - delegated to intg-test-executer.sh
#   teardown    - run post actions (stack deletion / log handling)
#   ""|all      - clone, run the whole executer flow, then post actions (legacy default;
#                 not used by the pipeline, kept for manual invocation)
# --------------------------------------------------------------------------------------

deploymentName=$1
productRepository=$2
productTestBranch=$3
productTestScript=$4
productTestGroup=$5
phase=$6
currentScript=$(dirname $(realpath "$0"))

deploymentDirectory="${WORKSPACE}/deployment/${deploymentName}"
parameterFilePath="${deploymentDirectory}/parameters.json"
testOutputDir="${deploymentDirectory}/outputs"
productDirectory="product-apim"

source ${currentScript}/common-functions.sh

productDirectoryLocation=""

function cloneTestRepo(){
    local githubUsername=$(extractParameters "GithubUserName" ${parameterFilePath})
    local githubPassword=$(extractParameters "GithubPassword" ${parameterFilePath})
    local cloneString=$(echo ${productRepository} | sed  's#https://#&'${githubUsername}':'${githubPassword}@'#')

    log_info "Cloning product repo to get test scripts"
    log_info "Product repo ${productRepository}"

    if [ ! -d  "${deploymentDirectory}/${productDirectory}" ];
     then
      git -C ${deploymentDirectory} clone ${cloneString} --branch ${productTestBranch}
      if [[ $? != 0 ]];
        then
          # Teardown is owned by the pipeline's Teardown stage - just fail the phase.
          log_error "Testing repo clone failed! Please check if the Git credentials or the test repo name is correct."
          exit 1
        else
          log_info "Cloning the test repo was successfull!"
      fi
    fi

    local repoName="$(basename ${productRepository} .git)"

    log_info "Product repo name ${repoName}"

    productDirectoryLocation="${deploymentDirectory}/${repoName}"
}

function prepareOutputDir(){
    log_info "Creating output directory"
    if [ -d "${testOutputDir}" ]; then
        log_error "Output directory already exists. Removing the existing output directory."
        rm -r "${testOutputDir}"
    fi
    mkdir ${testOutputDir}
}

# Delegate a single phase to the executer. Returns the executer's exit code.
function runExecuterPhase(){
    local execPhase=$1
    log_info "Executing scenario test phase '${execPhase}' for ${productTestGroup}!"
    bash ${currentScript}/intg-test-executer.sh "${deploymentDirectory}" "${testOutputDir}" "${productTestGroup}" "${execPhase}"
}

function runPostActions(){
    log_info "Executing post actions!"
    bash ${currentScript}/post-actions.sh ${deploymentName}
}

# Legacy combined flow: prepare outputs, run every executer phase, then post actions
# regardless of the test result. NOT used by the pipeline (integration.groovy always
# passes an explicit phase) - kept only for manual invocation.
function deploymentTest(){
    prepareOutputDir
    runExecuterPhase "all"
    if [[ $? != 0 ]];
    then
        log_error "Test Execution Failed!"
        runPostActions
        exit 1
    else
        log_info "Test Execution Passed!"
        runPostActions
    fi
}

function main(){
    case "${phase}" in
        clone)
            cloneTestRepo ;;
        setup)
            prepareOutputDir
            runExecuterPhase "setup" || exit 1 ;;
        update)
            runExecuterPhase "update" || exit 1 ;;
        provisiondb)
            runExecuterPhase "provisiondb" || exit 1 ;;
        test)
            runExecuterPhase "test" || exit 1 ;;
        collect)
            # Best-effort report collection; never fail the build for this.
            runExecuterPhase "collect" || log_info "Report collection failed (best-effort); continuing" ;;
        teardown)
            runPostActions ;;
        ""|all)
            cloneTestRepo
            deploymentTest ;;
        *)
            log_error "Unknown phase: ${phase}"
            exit 1 ;;
    esac
}

main
