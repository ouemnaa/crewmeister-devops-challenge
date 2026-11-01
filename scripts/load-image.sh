#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
mkdir -p .local

fail() {
    echo "$*" >&2
    exit 1
}

mode="${CREWMEISTER_IMAGE_MODE:-auto}"
repository="${CREWMEISTER_IMAGE_REPOSITORY:-ghcr.io/ouemnaa/crewmeister-devops-challenge}"
tag="${CREWMEISTER_IMAGE_TAG:-$(git rev-parse HEAD)}"
case "$mode" in auto|local|registry) ;; *) fail 'CREWMEISTER_IMAGE_MODE must be auto, local, or registry.' ;; esac
[[ "$repository" =~ ^[a-z0-9][a-z0-9./:_-]*$ ]] || fail 'Invalid image repository.'
[[ "$tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || fail 'Invalid image tag.'

source_paths=(Dockerfile .dockerignore pom.xml mvnw .mvn src)
source_changes="$(git status --porcelain --untracked-files=normal -- "${source_paths[@]}")"
use_registry=false
if [[ "$mode" == registry || ( "$mode" == auto && -z "$source_changes" ) ]]; then
    echo "Checking registry image $repository:$tag"
    if docker pull "$repository:$tag" >.local/image-pull.log 2>.local/image-pull.err; then
        use_registry=true
    elif [[ "$mode" == registry ]]; then
        fail 'Registry image could not be pulled. See .local/image-pull.err.'
    fi
fi

if [[ "$use_registry" == true ]]; then
    pull_policy=IfNotPresent
else
    echo 'Building the current checkout locally and loading it into Kind.'
    source_files="$(git ls-files --cached --others --exclude-standard -- "${source_paths[@]}")"
    while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        hash="$(git hash-object -- "$file")"
        printf '%s %s\n' "$file" "$hash"
    done <<< "$source_files" >.local/image-sources
    source_hash="$(git hash-object -- .local/image-sources)"
    repository=crewmeister-app
    tag="local-$source_hash"
    pull_policy=Never
    docker build --tag "$repository:$tag" .
fi

kind load docker-image "$repository:$tag" --name crewmeister
printf '{"image_repository":"%s","image_tag":"%s","image_pull_policy":"%s"}\n' \
    "$repository" "$tag" "$pull_policy" >.local/image.auto.tfvars.json
echo "Image ready: $repository:$tag ($pull_policy)"
