#!/bin/bash -eu

# build_alpine_golang builds the docker image that supports compiling golang files on alpine linux
function build_alpine_golang {
    local readonly no_cache_flag=${1}
	local readonly package_name=${2}
	local readonly package_push=${3}
	local readonly package_version=${4}
    local readonly package_is_latest=${5:-}

    # Initialise docker passwords
    procat_ci_docker_init

    # Create the package downloads directory it if doesn't exist already
    mkdir -p ${EXEC_CI_SCRIPT_PATH}/downloads/

    # Remove any existing files from the container's download directory
    rm -f ${EXEC_CI_SCRIPT_PATH}/downloads/*

    # awk is necessary to remove the comment line.
    #  e.g.  # Host gitlab.example.com found: line 52
    local readonly sshkey_gitlab_server=$(ssh-keygen -H -F ${PROCAT_CI_GIT_SERVER} | awk 'NR==2')
    local readonly sshkey_github_server=$(ssh-keygen -H -F github.com | awk 'NR==2')

    # Copy files that can be utilised in the dockerfile to the container's download directory
    echo ${sshkey_gitlab_server} > ${EXEC_CI_SCRIPT_PATH}/downloads/known_hosts
    echo ${sshkey_github_server} >> ${EXEC_CI_SCRIPT_PATH}/downloads/known_hosts

    # get the version of the latest badger release
    local readonly badger_project_id=45
    local badger_release_tag=$(gitlab_get_project_latest_release_tag ${GL_TOKEN} ${badger_project_id}) || return $?
    pc_log "latest release tag                : badger/${badger_release_tag}"

    # get the build job id associated with a release tag
    local readonly build_job_name="build"
    local badger_build_job_id=$(gitlab_get_release_build_job_id ${badger_project_id} "badger" ${badger_release_tag} ${build_job_name} ) || return $?

    # Download the latest badger release
    local readonly badger_version_without_v="${badger_release_tag:1}"
    local readonly badger_file_name="badger-linux-amd64-${badger_version_without_v}.tar.gz"
    local readonly badger_file_path="${EXEC_CI_SCRIPT_PATH}/downloads/${badger_file_name}"
    local readonly badger_artifacts_uri=$(gitlab_project_uri ${badger_project_id} /jobs/${badger_build_job_id}/artifacts/bin) || return $?

    pc_log "downloading badger                : ${_gitlab_api_url}${badger_artifacts_uri}/${badger_file_name}"
    curl --header "PRIVATE-TOKEN: ${GL_TOKEN}" -o ${badger_file_path} -jksSL "${_gitlab_api_url}${badger_artifacts_uri}/${badger_file_name}"

    # Extract the badger executable from the archive
    pc_log "extracting badger from archive    : ${badger_file_path}"
    tar -zxvf ${badger_file_path} -C "${EXEC_CI_SCRIPT_PATH}/downloads" badger

    local readonly alpine_version="3.19"
    local readonly golang_image="golang:${package_version}-alpine${alpine_version}"
    local readonly base_image="${PROCAT_CI_REGISTRY_SERVER}/procat/docker/alpine-bash:latest"
    local readonly build_args="--build-arg base_image=${base_image} --build-arg golang_image=${golang_image}"

    # Build the docker image
	procat_ci_docker_build_image ${no_cache_flag} ${package_name} ${package_push} ${package_version} ${package_is_latest} "${build_args}"
}

# configure_ci_environment is used to configure the CI environment variables
function configure_ci_environment {
    #
    # Check the pre-requisite environment variables have been set
    # PROCAT_CI_SCRIPTS_PATH would typically be set in .bashrc or .profile
    # 
    if [ -z ${PROCAT_CI_SCRIPTS_PATH+x} ]; then
        echo "ERROR: A required CI environment variable has not been set : PROCAT_CI_SCRIPTS_PATH"
        echo "       Has '~/.procat_ci_env.sh' been sourced into ~/.bashrc or ~/.profile?"
        env | grep "PROCAT_CI"
        return 1
    fi

    # Configure the build environment if it hasn't been configured already
    source "${PROCAT_CI_SCRIPTS_PATH}/set_ci_env.sh"
}

function build {
    #
    # configure_ci_environment is used to configure the CI environment variables
    # and load the CI common functions
    #
    configure_ci_environment || return $?

    # Use the GITLAB API
    source "${PROCAT_CI_SCRIPTS_PATH}/api/gitlab.sh"

    # Configure variables required by gitlab API
    local _gitlab_api_url="$(gitlab_api_url ${PROCAT_CI_GIT_SERVER})"

    # For testing purposes, default the package name
	if [ -z "${1-}" ]; then
        local package_name=${PROCAT_CI_REGISTRY_SERVER}/procat/docker/alpine-golang
        pc_log "package_name (default)           : $package_name"
	else
		local package_name=${1}
        pc_log "package_name                     : $package_name"
    fi

    # For testing purposes, default the package version
	if [ -z "${2-}" ]; then
        local package_version="1.21.6"
        pc_log "package_version (default)        : $package_version"
	else
		local package_version=${2}
        pc_log "package_version                  : $package_version"
    fi
    pc_log ""

	# Determine whether the --no-cache command line option has been specified.
	# If it has, attempts to download files from the internet are always made.
	if [ -z "${3-}" ]; then
		local no_cache_flag="false"
	else
		local no_cache_flag=$([ "$3" == "--no-cache" ] && echo "true" || echo "false")
	fi

    # get the upstream branch
    if [ -z "${CI_COMMIT_BRANCH-}" ]; then
        local readonly upstream_branch="$(cut -d "/" -f2 <<< $(git rev-parse --abbrev-ref --symbolic-full-name @{u}))"
    else
        local readonly upstream_branch="${CI_COMMIT_BRANCH}"
    fi
    pc_log "upstream_branch                  : $upstream_branch"

    # Build the docker image
	build_alpine_golang ${no_cache_flag} ${package_name} push ${package_version} latest
}

# $1 : (Mandatory) Package Name (registry.projectcatalysts.prv/procat/docker/alpine-golang)
# $2 : (Mandatory) Package Version (e.g. 3.14.2)
# $3 : (Optional) --no-cache
build ${1:-} ${2:-} ${3:-}
