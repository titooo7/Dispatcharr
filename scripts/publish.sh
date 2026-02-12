#!/bin/bash
# scripts/publish.sh - Automate building and pushing Dispatcharr images to GHCR

set -e

REPO_OWNER="titooo7"
REPO_NAME="dispatcharr"
BASE_TAG="base"
APP_TAG="latest"

usage() {
    echo "Usage: $0 [option]"
    echo "Options:"
    echo "  app    Build and push the application image (most common)"
    echo "  base   Build and push the base image (use if dependencies changed)"
    echo "  all    Build and push both images"
    exit 1
}

if [ -z "$1" ]; then
    usage
fi

build_base() {
    echo "🚀 Building Base Image: ghcr.io/$REPO_OWNER/$REPO_NAME:$BASE_TAG"
    docker build -f docker/DispatcharrBase -t ghcr.io/$REPO_OWNER/$REPO_NAME:$BASE_TAG .
    docker tag ghcr.io/$REPO_OWNER/$REPO_NAME:$BASE_TAG dispatcharr:base
    echo "📤 Pushing Base Image to GHCR..."
    docker push ghcr.io/$REPO_OWNER/$REPO_NAME:$BASE_TAG
}

build_app() {
    echo "🚀 Building App Image..."
    # We use DOCKER_BUILDKIT=0 to ensure local base image resolution works reliably in all environments
    DOCKER_BUILDKIT=0 docker compose -f docker/docker-compose.repostudy_aio.yml build
    
    echo "🏷️ Tagging App Image: ghcr.io/$REPO_OWNER/$REPO_NAME:$APP_TAG"
    docker tag docker-dispatcharr_repostudy:latest ghcr.io/$REPO_OWNER/$REPO_NAME:$APP_TAG
    
    echo "📤 Pushing App Image to GHCR..."
    docker push ghcr.io/$REPO_OWNER/$REPO_NAME:$APP_TAG
}

case "$1" in
    base)
        build_base
        ;;
    app)
        build_app
        ;;
    all)
        build_base
        build_app
        ;;
    *)
        usage
        ;;
esac

echo "✅ Done!"
