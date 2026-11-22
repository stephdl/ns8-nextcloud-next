#!/bin/bash

# Terminate on error
set -e

# Prepare variables for later use
images=()
# The image will be pushed to GitHub container registry
repobase="${REPOBASE:-ghcr.io/stephdl}"
# Configure the image name
reponame="nextcloud-next"

# Create a new empty container image
container=$(buildah from scratch)

# Node.js 25+ no longer ships Corepack, install it from npm
# renovate: datasource=npm packageName=corepack
corepack_version=0.36.0

# Reuse existing nodebuilder-nextcloud-next container, to speed up builds
if ! buildah containers --format "{{.ContainerName}}" | grep -q nodebuilder-nextcloud-next; then
    echo "Pulling NodeJS runtime..."
    buildah from --name nodebuilder-nextcloud-next -v "${PWD}:/usr/src:Z" docker.io/library/node:26.13.1-slim
    buildah run nodebuilder-nextcloud-next sh -c "npm install -g corepack@${corepack_version} && corepack enable"
fi

redis_image="docker.io/redis:8.10.3-alpine"
mariadb_image="docker.io/mariadb:12.3.3"
nginx_image="docker.io/nginx:1.30.7-alpine"
harp_image="ghcr.io/nextcloud/nextcloud-appapi-harp:v0.4.8"

# Read the versions from the image tags, so Renovate keeps the About page in sync
nextcloud_version=$(sed -n 's/^FROM .*nextcloud:\([0-9.]*\)-.*/\1/p' nextcloud/Dockerfile)
notify_push_version=$(sed -n 's/^ARG NOTIFY_PUSH_VERSION="\(.*\)"/\1/p' notify_push/Dockerfile)

echo "Build static UI files with node..."
buildah run \
    --env="NODE_OPTIONS=--openssl-legacy-provider" \
    --env="VUE_APP_NEXTCLOUD_VERSION=${nextcloud_version}" \
    --env="VUE_APP_MARIADB_VERSION=${mariadb_image##*:}" \
    --env="VUE_APP_REDIS_VERSION=${redis_image##*:}" \
    --env="VUE_APP_NGINX_VERSION=${nginx_image##*:}" \
    --env="VUE_APP_NOTIFY_PUSH_VERSION=${notify_push_version}" \
    nodebuilder-nextcloud-next sh -c "cd /usr/src/ui && yarn install && yarn build"

# Add imageroot directory to the container image
buildah add "${container}" imageroot /imageroot
buildah add "${container}" ui/dist /ui
# Setup the entrypoint, reserve two TCP ports (web and HaRP tunnel) and set a rootless container
buildah config --entrypoint=/ \
    --label="org.nethserver.authorizations=traefik@any:routeadm cluster:accountconsumer" \
    --label="org.nethserver.tcp-ports-demand=2" \
    --label="org.nethserver.rootfull=0" \
    --label="org.nethserver.volumes=nextcloud-app-data" \
    --label="org.nethserver.min-core=3.20.1" \
    --label="org.nethserver.images=${redis_image} ${mariadb_image} ${nginx_image} ${harp_image} ${repobase}/nextcloud-next-app:${IMAGETAG} ${repobase}/nextcloud-next-notify_push:${IMAGETAG}" \
    "${container}"
# Commit the image
buildah commit "${container}" "${repobase}/${reponame}"

# Append the image URL to the images array
images+=("${repobase}/${reponame}")

# Build nextcloud-next-app image
pushd nextcloud
buildah build -t ${repobase}/nextcloud-next-app
popd

# Append the image URL to the images array
images+=("${repobase}/nextcloud-next-app")

# Build notify_push image (Files High Performance Backend)
pushd notify_push
buildah build -t ${repobase}/nextcloud-next-notify_push
popd

# Append the image URL to the images array
images+=("${repobase}/nextcloud-next-notify_push")

#
# NOTICE:
#
# It is possible to build and publish multiple images.
#
# 1. create another buildah container
# 2. add things to it and commit it
# 3. append the image url to the images array
#

#
# Setup CI when pushing to Github.
# Warning! docker::// protocol expects lowercase letters (,,)
if [[ -n "${CI}" ]]; then
    # Set output value for Github Actions
    printf "images=%s\n" "${images[*],,}" >> "${GITHUB_OUTPUT}"
else
    # Just print info for manual push
    printf "Publish the images with:\n\n"
    for image in "${images[@],,}"; do printf "  buildah push %s docker://%s:%s\n" "${image}" "${image}" "${IMAGETAG:-latest}" ; done
    printf "\n"
fi
