#!/bin/bash
set -ueE -o pipefail

# =====================================
# AUTOMATIC GITHUB ENVIRONMENT VARIABLES
# https://docs.github.com/en/free-pro-team@latest/actions/reference/environment-variables

# GITHUB_REPOSITORY
# GITHUB_RUN_ID
# GITHUB_SHA
# GITHUB_REF

# =====================================
# MANUAL GITHUB CONTEXT VARIABLES
# https://docs.github.com/en/free-pro-team@latest/actions/reference/context-and-expression-syntax-for-github-actions

# GH_EVENT_NAME: ${{github.event_name}}

# =====================================
# MANUAL ENVIRONMENT VARIABLES

# NPM_AUTH_TOKEN
# NPM_BRANCH_TAG
# BEVRY_CDN_TOKEN

# =====================================
# LOCAL ENVIRONMENT VARIABLES

REPO_JOB_ID="$GITHUB_RUN_ID"
REPO_SLUG="$GITHUB_REPOSITORY"
REPO_SHA="$GITHUB_SHA" # "$(git rev-parse HEAD)"
REPO_NAME="${REPO_SLUG#*/}"
REPO_TAG=""
REPO_BRANCH=""
REPO_COMMIT=""
if [[ "$GITHUB_REF" == "refs/tags/"* ]]; then
	REPO_TAG="${GITHUB_REF#"refs/tags/"}"
elif [[ "$GITHUB_REF" == "refs/heads/"* ]]; then
	REPO_BRANCH="${GITHUB_REF#"refs/heads/"}"
	REPO_COMMIT="$GITHUB_SHA"
else
	echo "unknown GITHUB_REF=$GITHUB_REF"
	exit 1
fi

# =====================================
# CHECKS

if [[ "$REPO_BRANCH" = *"dependabot"* ]]; then
	echo "skipping as running on a dependabot branch"
	exit 0
elif test -z "$NPM_AUTH_TOKEN"; then
	echo "you must provide NPM_AUTH_TOKEN"
	exit 1
fi

# =====================================
# RUN

# # login
# # despite both `NODE_AUTH_TOKEN` and `NPM_TOKEN` being used in official documentation
# # they both result in a `404 Not Found - PUT` error upon publish
# # https://github.com/bevry/es-versions/runs/1378842251?check_suite_focus=true#step:7:39
# # https://github.com/bevry/es-versions/runs/1378917476?check_suite_focus=true#step:7:40
# # hence the need for the following login code below
echo "creating npmrc with npm auth token..."
echo "//registry.npmjs.org/:_authToken=$NPM_AUTH_TOKEN" > "$HOME/.npmrc"
echo "logged into npm as: $(npm whoami)"

# @todo simplify this, and consider making it only run on the default branch
# check if we wish to tag the current branch
if test -n "${NPM_BRANCH_TAG:-}"; then
	branch="${NPM_BRANCH_TAG%:*}"
	if test "$branch" = "$REPO_BRANCH"; then
		tag="${NPM_BRANCH_TAG#*:}"
	fi
fi

if test -n "${REPO_TAG-}" -o -n "${tag-}"; then
	echo "releasing to npm..."

	# not repo tag, is branch tag
	if test -z "${REPO_TAG-}" -a -n "${tag-}"; then
		echo "bumping the npm version..."
		version="$(node -e "console.log(require('./package.json').version)")"
		time="$(date +%s)"
		next="${version%-*}-${tag}.${time}.${REPO_SHA}"  # version trims anything after -
		npm version "${next}" --git-tag-version=false
		echo "publishing branch ${branch} to tag ${tag} with version ${next}..."
		npm publish --access public --tag "${tag}"

	# publish package.json
	else
		echo "publishing the local package.json version..."
		npm publish --access public
	fi

	echo "...released to npm"
else
	echo "no need for release to npm"
fi

# @todo consider making this its own script
# publish to bevry cdn
# used as an alternative to surge for documentation
# published to npm, with docs and whatnot included in the package
# and serves it via cdn.bevry.me
if test -n "${BEVRY_CDN_TOKEN-}"; then
	echo 'publishing to bevry cdn...'

	echo "prepping for cdn..."
	f="./.npmignore"
	n="$(mktemp)"
	o="$(mktemp)"
	node -e "process.stdout.write(require('fs').readFileSync('$f', 'utf8').replace(/# [-=\s]+# CDN Inclusions.+?[^#][^ ][^-=]+/, ''))" > "$n"
	mv "$f" "$o"
	mv "$n" "$f"

	echo "versioning for cdn..."
	tag="cdn"
	version="$(node -e "process.stdout.write(require('./package.json').version)")"
	time="$(date +%s)"
	cdn="${version%-*}-${tag}.${time}.${REPO_JOB_ID}"  # version trims anything after -
	npm version "${cdn}" --git-tag-version=false

	echo "publishing to tag ${tag} with version ${cdn}..."
	npm publish --access public --tag "${tag}"

	echo "adding cdn aliases..."
	packageName="$(node -e "process.stdout.write(require('./package.json').name)")"
	target="${packageName}@${cdn}"

	if test -n "${REPO_BRANCH-}"; then
		echo "aliasing $REPO_NAME/$REPO_BRANCH to ${target}"
		curl -d "alias=$REPO_NAME/$REPO_BRANCH" -d "target=${target}" -d "token=${BEVRY_CDN_TOKEN}" https://cdn.bevry.me
	fi
	if test -n "${REPO_TAG-}"; then
		echo "aliasing $REPO_NAME/$REPO_TAG to ${target}"
		curl -d "alias=$REPO_NAME/$REPO_TAG" -d "target=${target}" -d "token=${BEVRY_CDN_TOKEN}" https://cdn.bevry.me
	fi
	if test -n "${REPO_COMMIT-}"; then
		echo "aliasing $REPO_NAME/$REPO_COMMIT to ${target}"
		curl -d "alias=$REPO_NAME/$REPO_COMMIT" -d "target=${target}" -d "token=${BEVRY_CDN_TOKEN}" https://cdn.bevry.me
	fi

	echo 'resetting cdn changes...'
	git reset --hard

	echo '...published to bevry cdn'
fi
