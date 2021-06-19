#!/usr/bin/env bash

function security_checker_installer() {
  URL="https://github.com/fabpot/local-php-security-checker/releases/download/v1.0.0/local-php-security-checker_1.0.0_linux_amd64"
  if [ ! -f $security_checker ]; then
    curl -L -s $URL -o $security_checker
    chmod +x $security_checker
    echo "script downloaded"
  fi
}

function repository_clone() {
  if [ -d "$project_path" ]; then
    rm -rf "$project_path"
  fi

  git clone --depth=1 "$repository" "$project_path"
}

function branch_exists() {
  git -C "${project_path}" ls-remote --heads "$repository" ${branch} | grep ${branch} >/dev/null
  [[ "$?" == "1" ]] && EXISTS=false || return EXISTS=true
}

function check_error() {
  if [ -z "$1" ]; then
    echo "a curl content should be passed as parameter"
    exit 1
  fi

  if [ -z "$2" ]; then
    echo "an error description should be passed as parameter"
    exit 1
  fi

  error_message=$(echo "$1" | jq -r '.message?' | sed 's/"// ')
  if [ "$error_message" != "" ] && [ "$error_message" != null ]; then
    echo "Failed to $2 using GitLab API : $error_message"
    exit 1
  fi
}

function get_repository_id() {
  projects=$(curl -s --header "PRIVATE-TOKEN: $GITLAB_PRIVATE_TOKEN" "https://gitlab.com/api/v4/projects?search=$project")
  check_error "$projects" "fetch the repository id"

  project_id=$(echo "$projects" | jq --arg name "$repository" '.[] | select(.ssh_url_to_repo == $name)' | jq .id)
}

function create_merge_request() {
  merge_request_query=$(curl -s --location --request POST "https://gitlab.com/api/v4/projects/$project_id/merge_requests" \
    --header "PRIVATE-TOKEN: $GITLAB_PRIVATE_TOKEN" \
    --header 'Content-Type: application/json' \
    --data-raw '{
      "source_branch": "'"$branch"'",
      "target_branch": "develop",
      "title": "[NOISSUE] - Fix CVE",
      "squash": true,
      "remove_source_branch": true
    }')

  check_error "$merge_request_query" "create the merge request"
  echo "Merge Request for project $project : $(echo "$merge_request_query" | jq -r .web_url)"
}

function scan_repositories() {
  for repository in "${repositories[@]}"; do
    project=$(echo "$repository" | sed "s/git@gitlab.com://" | sed "s/.git//" | cut -d "/" -f 2)
    project_path="working_dir/$project"

    echo "Scanning $project"

    repository_clone
    branch_exists

    if [ "true" = $EXISTS ]; then
      echo "Branch already exists"
      continue
    fi

    git -C "${project_path}" checkout -b develop
    git -C "${project_path}" pull origin develop

    scan_result=$(./$security_checker --path="$project_path" --format=json)
    has_result=$(echo $scan_result | jq keys[])

    if [ "$has_result" = "" ]; then
      echo "No CVE for $project"
      continue
    fi

    packages=$(echo $scan_result | jq -r 'keys | join(" ")')
    echo "$packages"
    composer update -d "$project_path" --no-plugins "$packages"

    if [[ ! $(git -C "${project_path}" status --porcelain) ]]; then
      echo "No changes after composer update on $project"
      continue
    fi

    git -C "${project_path}" checkout -b "$branch"
    git -C "${project_path}" add composer.lock
    git -C "${project_path}" commit -m "[NOISSUE] - Fix CVE"
    git -C "${project_path}" push origin "$branch"

    get_repository_id
    create_merge_request

    rm -rf "$project_path" # Clean working_dir

  done
}

if [ -z "$GITLAB_PRIVATE_TOKEN" ]; then
  echo "GITLAB_PRIVATE_TOKEN should be defined"
  exit 1
fi

security_checker="local-php-security-checker"
branch="feature/NOISSUE-SSU-fix-cve"

repositories=(
  # TODO fill git remote urls here
)

if [ 0 = ${#repositories[@]} ]; then
  echo "You have to fill the repositories array before running this script"
  exit 1
fi

security_checker_installer
scan_repositories
