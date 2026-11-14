#!/usr/bin/env bash
#
# Bootstrap a Scaleway Organization for the foundation module.
#
# Creates (or repairs) the few resources Terraform needs before it can run, all named
# after --name (default: tf-foundation):
#   1. a "<name>" Project (or the Organization's "default" Project, with --use-default-project);
#   2. a versioned, private Object Storage bucket "<name>-tfstate-<region>-<org8>" for the
#      Terraform state;
#   3. an IAM application "<name>-ci" used by Terraform;
#   4. the membership of that application in the "Administrators" group;
#   5. an API key "<name>-ci" for that application, with the Project of 1. as default Project;
#   6. a protected Secret Manager secret "<name>-ci-key", and 7. a version of it holding
#      the API key.
#
# The script is idempotent: every resource is looked up before being created, and
# re-running it only fixes what is missing or has drifted. It only manages resources
# carrying the ownership mark "owner=foundation-bootscript" (a tag, or the description
# for resources without tags) and refuses to touch same-named resources without it.
#
# Credentials: the standard scw CLI chain is used (SCW_ACCESS_KEY / SCW_SECRET_KEY
# environment variables, or a scw profile). They must belong to an Organization admin.
#
# Usage: scripts/bootstrap.sh --organization-id <id> [--name <name>] [--profile <name>]
#          [--region <region>] [--use-default-project] [--dry-run] [--yes]
#
# Requirements: bash >= 3.2, scw CLI >= 2.65.

set -euo pipefail

# --- Settings -----------------------------------------------------------------------

readonly OWNER_TAG="owner=foundation-bootscript"
readonly DEFAULT_NAME="tf-foundation"
readonly DEFAULT_REGION="fr-par"
readonly ADMIN_GROUP_NAME="Administrators"

readonly UUID_REGEX='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
readonly ACCESS_KEY_REGEX='^SCW[A-Z0-9]{17}$'
readonly REGION_REGEX='^[a-z]{2}-[a-z]{3}$'
# The name prefixes the bucket name "<name>-tfstate-<region>-<org8>", limited to 63
# characters: 39 characters at most, in the characters allowed for bucket names.
readonly NAME_REGEX='^[a-z0-9]([a-z0-9-]{0,37}[a-z0-9])?$'

# Command line options.
ORGANIZATION_ID=""
NAME="${DEFAULT_NAME}"
REGION=""
PROFILE=""
USE_DEFAULT_PROJECT=false
DRY_RUN=false
ASSUME_YES=false

# Resource names and descriptions, derived from the options by derive_names.
PROJECT_NAME=""
PROJECT_DESCRIPTION=""
BUCKET_NAME=""
APPLICATION_NAME=""
APPLICATION_DESCRIPTION=""
API_KEY_DESCRIPTION=""
SECRET_NAME=""
SECRET_DESCRIPTION=""

SCW_GLOBAL_ARGS=()
CREDENTIALS_SOURCE=""
REGION_SOURCE=""
BEARER_TYPE=""
BEARER_ID=""
BEARER_NAME=""
CHANGES=0

PROJECT_ID=""
APPLICATION_ID=""
SECRET_ID=""

# --- Helpers ------------------------------------------------------------------------

info() { printf '%s\n' "$*" >&2; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}
step() { printf '\n==> %s\n' "$*" >&2; }
ok() { printf '    ok: %s\n' "$*" >&2; }

# Announce a change. Changes are counted in the main shell, so this must not be
# called from a command substitution.
change() {
  CHANGES=$((CHANGES + 1))
  if [[ "${DRY_RUN}" == true ]]; then
    printf '    [dry-run] would %s\n' "$*" >&2
  else
    printf '    %s\n' "$*" >&2
  fi
}

# Read-only scw call: always executed, even in dry-run mode.
scw_read() {
  scw ${SCW_GLOBAL_ARGS[@]+"${SCW_GLOBAL_ARGS[@]}"} "$@"
}

# Mutating scw call: skipped in dry-run mode. Never pass a secret as an argument.
scw_write() {
  if [[ "${DRY_RUN}" == true ]]; then
    return 0
  fi
  scw ${SCW_GLOBAL_ARGS[@]+"${SCW_GLOBAL_ARGS[@]}"} "$@"
}

# Keep only the lines of a "|"-separated listing whose given field equals a value.
# scw name filters may match partially, this enforces an exact match.
field_equals() {
  awk -F'|' -v field="$1" -v value="$2" '$field == value'
}

count_lines() {
  if [[ -z "$1" ]]; then
    echo 0
  else
    printf '%s\n' "$1" | wc -l | tr -d ' '
  fi
}

has_owner_mark() {
  case "$1" in
    *"${OWNER_TAG}"*) return 0 ;;
    *) return 1 ;;
  esac
}

not_owned() {
  die "$1 already exists but has no '${OWNER_TAG}' mark. It was not created by this script: rename it, or add the mark if this script should manage it."
}

usage() {
  cat <<EOF
Usage: $(basename "$0") --organization-id <id> [options]

Bootstrap (or repair) a Scaleway Organization for the foundation module.

Required:
  --organization-id <id>  Organization to bootstrap. Must match the Organization of the
                          credentials in use.

Options:
  --name <name>           Name of the bootstrap resources (default: ${DEFAULT_NAME}). Project
                          "<name>", bucket "<name>-tfstate-<region>-<org8>", IAM application
                          and API key "<name>-ci", secret "<name>-ci-key". Lowercase letters,
                          digits and hyphens, 39 characters at most.
  --use-default-project   Put the bucket and the secret in the Organization's "default"
                          Project instead of a dedicated "<name>" Project. Everyone with
                          access to that Project can then read the admin API key.
  --profile <name>        scw profile to use. Cannot be combined with the
                          SCW_ACCESS_KEY / SCW_SECRET_KEY environment variables.
  --region <region>       Region of the state bucket and of the secret. Defaults to
                          SCW_DEFAULT_REGION, then to the default region of the scw
                          profile, then to ${DEFAULT_REGION}.
  --dry-run               Only read the current state and show what would change.
  --yes                   Do not ask for confirmation before making changes.
  -h, --help              Show this help.

Credentials are read the same way as the scw CLI does: from the SCW_ACCESS_KEY and
SCW_SECRET_KEY environment variables, or from a scw profile. They must belong to an
Organization admin.
EOF
}

# --- Arguments and pre-flight checks ------------------------------------------------

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --organization-id | --name | --profile | --region)
        [[ $# -ge 2 && -n "$2" ]] || die "$1 requires a value."
        case "$1" in
          --organization-id) ORGANIZATION_ID="$2" ;;
          --name) NAME="$2" ;;
          --profile) PROFILE="$2" ;;
          --region) REGION="$2" ;;
        esac
        shift 2
        ;;
      --organization-id=*) ORGANIZATION_ID="${1#*=}" && shift ;;
      --name=*) NAME="${1#*=}" && shift ;;
      --profile=*) PROFILE="${1#*=}" && shift ;;
      --region=*) REGION="${1#*=}" && shift ;;
      --use-default-project) USE_DEFAULT_PROJECT=true && shift ;;
      --dry-run) DRY_RUN=true && shift ;;
      --yes) ASSUME_YES=true && shift ;;
      -h | --help) usage && exit 0 ;;
      *) usage >&2 && die "Unknown argument: $1" ;;
    esac
  done

  [[ -n "${ORGANIZATION_ID}" ]] || {
    usage >&2
    die "--organization-id is required."
  }
  [[ "${ORGANIZATION_ID}" =~ ${UUID_REGEX} ]] || die "Invalid Organization ID: ${ORGANIZATION_ID}"
  [[ "${NAME}" =~ ${NAME_REGEX} ]] ||
    die "Invalid name '${NAME}': use 1 to 39 lowercase letters, digits and hyphens, starting and ending with a letter or a digit."
  if [[ -n "${REGION}" ]]; then
    [[ "${REGION}" =~ ${REGION_REGEX} ]] || die "Invalid region: ${REGION}"
    REGION_SOURCE="--region"
  fi
}

# Region of the bucket and of the secret: --region, then SCW_DEFAULT_REGION, then the
# default region of the scw profile (when credentials come from a profile), then
# DEFAULT_REGION. Must run after resolve_credentials, which selects the profile.
resolve_region() {
  [[ -n "${REGION}" ]] && return 0
  local configured=""
  if [[ -n "${SCW_DEFAULT_REGION:-}" ]]; then
    configured="${SCW_DEFAULT_REGION}"
    REGION_SOURCE="SCW_DEFAULT_REGION"
  elif [[ "${CREDENTIALS_SOURCE}" != "environment variables" ]]; then
    configured="$(scw_read config get default-region 2>/dev/null || true)"
    REGION_SOURCE="${CREDENTIALS_SOURCE}"
  fi
  if [[ "${configured}" =~ ${REGION_REGEX} ]]; then
    REGION="${configured}"
  else
    [[ -z "${configured}" || "${configured}" == "-" ]] || die "Invalid region '${configured}' in ${REGION_SOURCE}."
    REGION="${DEFAULT_REGION}"
    REGION_SOURCE="built-in default"
  fi
}

derive_names() {
  PROJECT_NAME="${NAME}"
  PROJECT_DESCRIPTION="Foundation resources managed by scripts/bootstrap.sh. ${OWNER_TAG}"
  # Bucket names are global to Scaleway: the region and the start of the Organization
  # ID make it unique while keeping it short.
  BUCKET_NAME="${NAME}-tfstate-${REGION}-${ORGANIZATION_ID:0:8}"
  APPLICATION_NAME="${NAME}-ci"
  APPLICATION_DESCRIPTION="Identity used by Terraform to manage the Organization."
  # API keys have no name: the name goes in the description, with the ownership mark.
  API_KEY_DESCRIPTION="${APPLICATION_NAME} (${OWNER_TAG})"
  SECRET_NAME="${NAME}-ci-key"
  SECRET_DESCRIPTION="API key of the ${APPLICATION_NAME} IAM application."
}

check_dependencies() {
  command -v scw >/dev/null 2>&1 || die "The scw CLI is required: https://github.com/scaleway/scaleway-cli"
}

# Work out where the credentials come from, refusing ambiguous setups.
resolve_credentials() {
  local access_key configured_org

  if [[ -n "${SCW_ACCESS_KEY:-}" || -n "${SCW_SECRET_KEY:-}" ]]; then
    if [[ -n "${PROFILE}" || -n "${SCW_PROFILE:-}" ]]; then
      die "Credentials are set both in environment variables (SCW_ACCESS_KEY / SCW_SECRET_KEY) and through a profile (--profile / SCW_PROFILE). Use only one of them."
    fi
    [[ -n "${SCW_ACCESS_KEY:-}" && -n "${SCW_SECRET_KEY:-}" ]] ||
      die "SCW_ACCESS_KEY and SCW_SECRET_KEY must both be set."
    CREDENTIALS_SOURCE="environment variables"
    access_key="${SCW_ACCESS_KEY}"
  else
    if [[ -n "${PROFILE}" ]]; then
      SCW_GLOBAL_ARGS=(--profile "${PROFILE}")
      CREDENTIALS_SOURCE="scw profile '${PROFILE}'"
    elif [[ -n "${SCW_PROFILE:-}" ]]; then
      CREDENTIALS_SOURCE="scw profile '${SCW_PROFILE}' (from SCW_PROFILE)"
    else
      CREDENTIALS_SOURCE="scw default profile"
    fi
    access_key="$(scw_read config get access-key 2>/dev/null || true)"
  fi
  [[ "${access_key}" =~ ${ACCESS_KEY_REGEX} ]] ||
    die "No valid access key found in ${CREDENTIALS_SOURCE}."

  # A default Organization configured elsewhere must agree with --organization-id.
  configured_org="${SCW_DEFAULT_ORGANIZATION_ID:-}"
  if [[ -z "${configured_org}" && "${CREDENTIALS_SOURCE}" != "environment variables" ]]; then
    configured_org="$(scw_read config get default-organization-id 2>/dev/null || true)"
  fi
  if [[ "${configured_org}" =~ ${UUID_REGEX} && "${configured_org}" != "${ORGANIZATION_ID}" ]]; then
    die "The default Organization of ${CREDENTIALS_SOURCE} (${configured_org}) differs from --organization-id (${ORGANIZATION_ID})."
  fi

  # Listing the key within the Organization checks at once that the credentials work
  # and that they belong to that Organization.
  local key_info
  key_info="$(scw_read iam api-key list organization-id="${ORGANIZATION_ID}" access-keys.0="${access_key}" \
    -o template='{{ .UserID }}|{{ .ApplicationID }}')" ||
    die "Cannot list API keys of Organization ${ORGANIZATION_ID} with ${CREDENTIALS_SOURCE}. Check the credentials and that they belong to an Organization admin."
  key_info="$(printf '%s\n' "${key_info}" | sed '/^[[:space:]]*$/d')"
  [[ -n "${key_info}" ]] ||
    die "The credentials from ${CREDENTIALS_SOURCE} do not belong to Organization ${ORGANIZATION_ID}."

  local user_id="${key_info%%|*}" application_id="${key_info#*|}"
  if [[ "${user_id}" =~ ${UUID_REGEX} ]]; then
    BEARER_TYPE="user"
    BEARER_ID="${user_id}"
    BEARER_NAME="$(scw_read iam user get user-id="${user_id}" -o template='{{ .Email }}' 2>/dev/null || echo unknown)"
  elif [[ "${application_id}" =~ ${UUID_REGEX} ]]; then
    BEARER_TYPE="application"
    BEARER_ID="${application_id}"
    BEARER_NAME="$(scw_read iam application get application-id="${application_id}" -o template='{{ .Name }}' 2>/dev/null || echo unknown)"
  else
    die "Cannot identify the owner of the API key in use."
  fi
}

confirm() {
  info ""
  info "Organization: ${ORGANIZATION_ID}"
  info "Acting as:    ${BEARER_TYPE} ${BEARER_NAME} (${BEARER_ID})"
  info "Credentials:  ${CREDENTIALS_SOURCE}"
  info "Region:       ${REGION} (from ${REGION_SOURCE})"
  info "Name:         ${NAME}"
  if [[ "${USE_DEFAULT_PROJECT}" == true ]]; then
    info "Project:      default Project of the Organization (${ORGANIZATION_ID})"
    warn "With --use-default-project, the admin API key is stored in the default Project: everyone with access to secrets in that Project can read it and act as an Organization admin."
  else
    info "Project:      ${PROJECT_NAME}"
  fi
  if [[ "${DRY_RUN}" == true ]]; then
    info "Mode:         dry-run (nothing will be changed)"
    return 0
  fi
  [[ "${ASSUME_YES}" == true ]] && return 0
  [[ -t 0 ]] || die "No terminal to ask for confirmation. Use --yes to run non-interactively."
  local answer
  read -r -p "Bootstrap this Organization? [y/N] " answer
  [[ "${answer}" == "y" || "${answer}" == "Y" ]] || die "Aborted."
}

# --- Resources ----------------------------------------------------------------------

ensure_project() {
  if [[ "${USE_DEFAULT_PROJECT}" == true ]]; then
    use_default_project
    return 0
  fi

  step "Project '${PROJECT_NAME}'"
  local matches
  matches="$(scw_read account project list organization-id="${ORGANIZATION_ID}" name="${PROJECT_NAME}" \
    -o template='{{ .ID }}|{{ .Name }}|{{ .Description }}' | field_equals 2 "${PROJECT_NAME}")"

  case "$(count_lines "${matches}")" in
    0)
      change "create project '${PROJECT_NAME}'"
      PROJECT_ID="$(scw_write account project create organization-id="${ORGANIZATION_ID}" \
        name="${PROJECT_NAME}" description="${PROJECT_DESCRIPTION}" -o template='{{ .ID }}')"
      ;;
    1)
      PROJECT_ID="${matches%%|*}"
      has_owner_mark "${matches}" || not_owned "Project '${PROJECT_NAME}' (${PROJECT_ID})"
      ok "exists (${PROJECT_ID})"
      ;;
    *) die "Several Projects are named '${PROJECT_NAME}'. Rename the extra ones." ;;
  esac
}

# The default Project is created by Scaleway with the Organization, and shares its ID.
# The script did not create it and does not own it: it only checks that it exists.
use_default_project() {
  step "Default Project"
  local name
  name="$(scw_read account project get project-id="${ORGANIZATION_ID}" -o template='{{ .Name }}')" ||
    die "Cannot find the default Project of Organization ${ORGANIZATION_ID} (Project ID ${ORGANIZATION_ID})."
  PROJECT_ID="${ORGANIZATION_ID}"
  PROJECT_NAME="${name}"
  ok "exists (${PROJECT_ID}, named '${PROJECT_NAME}'), used as is"
}

ensure_bucket() {
  step "State bucket '${BUCKET_NAME}' (${REGION})"
  if [[ -z "${PROJECT_ID}" ]]; then
    change "create bucket '${BUCKET_NAME}' with versioning"
    return 0
  fi

  local output
  if output="$(scw_read object bucket get name="${BUCKET_NAME}" project-id="${PROJECT_ID}" region="${REGION}" \
    -o template='{{ .EnableVersioning }}|{{ range .Tags }}{{ .Key }}={{ .Value }},{{ end }}' 2>&1)"; then
    has_owner_mark "${output}" || not_owned "Bucket '${BUCKET_NAME}'"
    if [[ "${output%%|*}" == "true" ]]; then
      ok "exists, versioning enabled"
    else
      change "enable versioning on bucket '${BUCKET_NAME}'"
      scw_write object bucket update name="${BUCKET_NAME}" project-id="${PROJECT_ID}" region="${REGION}" \
        enable-versioning=true acl=private tags.0="${OWNER_TAG}" >/dev/null
    fi
  elif printf '%s' "${output}" | grep -qiE 'NoSuchBucket|not ?found|404'; then
    change "create bucket '${BUCKET_NAME}' with versioning"
    scw_write object bucket create name="${BUCKET_NAME}" project-id="${PROJECT_ID}" region="${REGION}" \
      enable-versioning=true acl=private tags.0="${OWNER_TAG}" >/dev/null
  else
    die "Cannot read bucket '${BUCKET_NAME}' (the name may be taken by another Organization): ${output}"
  fi
}

ensure_application() {
  step "IAM application '${APPLICATION_NAME}'"
  local matches
  matches="$(scw_read iam application list organization-id="${ORGANIZATION_ID}" name="${APPLICATION_NAME}" \
    -o template='{{ .ID }}|{{ .Name }}|{{ range .Tags }}{{ . }},{{ end }}' | field_equals 2 "${APPLICATION_NAME}")"

  case "$(count_lines "${matches}")" in
    0)
      change "create IAM application '${APPLICATION_NAME}'"
      APPLICATION_ID="$(scw_write iam application create organization-id="${ORGANIZATION_ID}" \
        name="${APPLICATION_NAME}" description="${APPLICATION_DESCRIPTION}" tags.0="${OWNER_TAG}" \
        -o template='{{ .ID }}')"
      ;;
    1)
      APPLICATION_ID="${matches%%|*}"
      has_owner_mark "${matches}" || not_owned "IAM application '${APPLICATION_NAME}' (${APPLICATION_ID})"
      ok "exists (${APPLICATION_ID})"
      ;;
    *) die "Several IAM applications are named '${APPLICATION_NAME}'. Rename the extra ones." ;;
  esac

  # Rotating the key of the application we are running as would cut the branch we sit on.
  if [[ "${BEARER_TYPE}" == "application" && "${BEARER_ID}" == "${APPLICATION_ID}" ]]; then
    die "The credentials in use belong to '${APPLICATION_NAME}' itself. Run this script with an Organization admin's own credentials."
  fi
}

ensure_admin_membership() {
  step "Membership of '${APPLICATION_NAME}' in group '${ADMIN_GROUP_NAME}'"
  local group_id
  group_id="$(scw_read iam group list organization-id="${ORGANIZATION_ID}" name="${ADMIN_GROUP_NAME}" \
    -o template='{{ .ID }}|{{ .Name }}' | field_equals 2 "${ADMIN_GROUP_NAME}" | cut -d'|' -f1)"
  [[ "$(count_lines "${group_id}")" == 1 ]] ||
    die "Expected exactly one IAM group named '${ADMIN_GROUP_NAME}' in the Organization."

  if [[ -z "${APPLICATION_ID}" ]]; then
    change "add '${APPLICATION_NAME}' to group '${ADMIN_GROUP_NAME}'"
    return 0
  fi
  local members
  members="$(scw_read iam group get group-id="${group_id}" -o template='{{ range .ApplicationIDs }}{{ . }} {{ end }}')"
  case " ${members} " in
    *" ${APPLICATION_ID} "*) ok "already a member" ;;
    *)
      change "add '${APPLICATION_NAME}' to group '${ADMIN_GROUP_NAME}'"
      scw_write iam group add-member group-id="${group_id}" application-id="${APPLICATION_ID}" >/dev/null
      ;;
  esac
}

ensure_secret() {
  step "Secret '${SECRET_NAME}' (${REGION})"
  if [[ -z "${PROJECT_ID}" ]]; then
    change "create protected secret '${SECRET_NAME}'"
    return 0
  fi

  local matches
  matches="$(scw_read secret secret list project-id="${PROJECT_ID}" name="${SECRET_NAME}" region="${REGION}" \
    -o template='{{ .ID }}|{{ .Name }}|{{ .Type }}|{{ .Protected }}|{{ range .Tags }}{{ . }},{{ end }}' |
    field_equals 2 "${SECRET_NAME}")"

  case "$(count_lines "${matches}")" in
    0)
      change "create protected secret '${SECRET_NAME}'"
      SECRET_ID="$(scw_write secret secret create project-id="${PROJECT_ID}" name="${SECRET_NAME}" \
        description="${SECRET_DESCRIPTION}" type=key_value protected=true tags.0="${OWNER_TAG}" \
        region="${REGION}" -o template='{{ .ID }}')"
      ;;
    1)
      SECRET_ID="$(printf '%s' "${matches}" | cut -d'|' -f1)"
      has_owner_mark "${matches}" || not_owned "Secret '${SECRET_NAME}' (${SECRET_ID})"
      [[ "$(printf '%s' "${matches}" | cut -d'|' -f3)" == "key_value" ]] ||
        die "Secret '${SECRET_NAME}' is not of type key_value. Delete it so it can be recreated."
      if [[ "$(printf '%s' "${matches}" | cut -d'|' -f4)" == "true" ]]; then
        ok "exists (${SECRET_ID}), protected"
      else
        change "enable protection on secret '${SECRET_NAME}'"
        scw_write secret secret protect secret-id="${SECRET_ID}" region="${REGION}" >/dev/null
      fi
      ;;
    *) die "Several secrets are named '${SECRET_NAME}'. Rename the extra ones." ;;
  esac
}

# A run with another region (or another Project) than the first one would create a
# second secret, rotate the API key into it and delete the key Terraform reads from the
# first secret. Before changing anything, refuse if this script's secret already lives
# somewhere else. Read-only.
check_secret_location() {
  local expected_project elsewhere
  if [[ "${USE_DEFAULT_PROJECT}" == true ]]; then
    expected_project="${ORGANIZATION_ID}"
  else
    expected_project="$(scw_read account project list organization-id="${ORGANIZATION_ID}" name="${PROJECT_NAME}" \
      -o template='{{ .ID }}|{{ .Name }}' | field_equals 2 "${PROJECT_NAME}" | cut -d'|' -f1)"
  fi
  elsewhere="$(scw_read secret secret list organization-id="${ORGANIZATION_ID}" name="${SECRET_NAME}" region=all \
    -o template='{{ .Region }}|{{ .ProjectID }}|{{ .Name }}|{{ range .Tags }}{{ . }},{{ end }}' |
    field_equals 3 "${SECRET_NAME}" |
    awk -F'|' -v region="${REGION}" -v project="${expected_project}" -v mark="${OWNER_TAG}" \
      'index($4, mark) && !($1 == region && $2 == project) { print "region " $1 ", Project " $2 }')"
  [[ -z "${elsewhere}" ]] ||
    die "Secret '${SECRET_NAME}' already exists in ${elsewhere//$'\n'/; }. Run the script with the same region and Project options as when it was created."
}

ensure_api_key() {
  step "API key of '${APPLICATION_NAME}'"
  if [[ -z "${APPLICATION_ID}" || -z "${SECRET_ID}" ]]; then
    change "create an API key for '${APPLICATION_NAME}' and store it in secret '${SECRET_NAME}'"
    return 0
  fi

  local keys stored_key=""
  keys="$(scw_read iam api-key list organization-id="${ORGANIZATION_ID}" bearer-type=application \
    bearer-id="${APPLICATION_ID}" -o template='{{ .AccessKey }}|{{ .DefaultProjectID }}|{{ .Description }}' |
    sed '/^[[:space:]]*$/d')"
  # Only the access key is read back from the secret, never the secret key.
  stored_key="$(scw_read secret version access secret-id="${SECRET_ID}" revision=latest_enabled \
    field=access_key raw=true region="${REGION}" 2>/dev/null | tr -d '[:space:]' || true)"

  local current
  current="$(printf '%s\n' "${keys}" | field_equals 1 "${stored_key}")"
  if [[ "${stored_key}" =~ ${ACCESS_KEY_REGEX} && -n "${current}" ]]; then
    ok "stored key ${stored_key} is valid"
    if [[ "$(printf '%s' "${current}" | cut -d'|' -f2)" != "${PROJECT_ID}" ]]; then
      change "set default project of key ${stored_key} to '${PROJECT_NAME}'"
      scw_write iam api-key update access-key="${stored_key}" default-project-id="${PROJECT_ID}" >/dev/null
    fi
  else
    change "create a new API key for '${APPLICATION_NAME}' and store it in secret '${SECRET_NAME}'"
    if [[ "${DRY_RUN}" != true ]]; then
      stored_key="$(rotate_api_key)"
    fi
  fi

  remove_stale_keys "${keys}" "${stored_key}"
}

# Create a new key and store it in the secret. Prints the new access key only.
rotate_api_key() {
  local created access_key secret_key
  created="$(scw_write iam api-key create application-id="${APPLICATION_ID}" default-project-id="${PROJECT_ID}" \
    description="${API_KEY_DESCRIPTION}" -o template='{{ .AccessKey }}|{{ .SecretKey }}')"
  access_key="${created%%|*}"
  secret_key="${created#*|}"
  unset created
  [[ "${access_key}" =~ ${ACCESS_KEY_REGEX} && "${secret_key}" =~ ${UUID_REGEX} ]] ||
    die "Unexpected output while creating the API key."

  # printf is a shell builtin: the secret key goes through a pipe, never through the
  # arguments of a process (which other users could see with ps).
  if ! printf '{"access_key":"%s","secret_key":"%s"}' "${access_key}" "${secret_key}" |
    scw_write secret version create secret-id="${SECRET_ID}" data=@/dev/stdin disable-previous=true \
      description="API key ${access_key}" region="${REGION}" >/dev/null; then
    scw_write iam api-key delete access-key="${access_key}" >/dev/null ||
      warn "Could not delete the unused API key ${access_key}: delete it manually."
    die "Could not store the new API key in secret '${SECRET_NAME}'."
  fi
  unset secret_key
  printf '%s' "${access_key}"
}

# Delete the keys this script created earlier, except the one in use.
remove_stale_keys() {
  local keys="$1" keep="$2" line access_key
  [[ -n "${keys}" ]] || return 0
  while IFS= read -r line; do
    access_key="${line%%|*}"
    [[ "${access_key}" == "${keep}" ]] && continue
    if has_owner_mark "${line}"; then
      change "delete stale API key ${access_key}"
      scw_write iam api-key delete access-key="${access_key}" >/dev/null
    else
      warn "API key ${access_key} of '${APPLICATION_NAME}' was not created by this script, leaving it untouched."
    fi
  done <<<"${keys}"
}

summary() {
  step "Summary"
  if [[ "${DRY_RUN}" == true ]]; then
    info "${CHANGES} change(s) would be made. Run again without --dry-run to apply them."
    return 0
  fi
  info "${CHANGES} change(s) made."
  # Same credentials as this run: only --profile has to be repeated, environment
  # variables and SCW_PROFILE are inherited.
  local profile_arg=""
  [[ -z "${PROFILE}" ]] || profile_arg=" --profile ${PROFILE}"
  cat >&2 <<EOF

Terraform API key: secret '${SECRET_NAME}' (${SECRET_ID}) in project '${PROJECT_NAME}', region ${REGION}.

To store it in your CI secrets, read its two fields with the same credentials:

  Access key: scw${profile_arg} secret version access secret-id=${SECRET_ID} revision=latest_enabled field=access_key raw=true region=${REGION}
  Secret key: scw${profile_arg} secret version access secret-id=${SECRET_ID} revision=latest_enabled field=secret_key raw=true region=${REGION}

Backend configuration for the Terraform state (Terraform >= 1.11):

  terraform {
    backend "s3" {
      bucket                      = "${BUCKET_NAME}"
      key                         = "foundation/terraform.tfstate"
      region                      = "${REGION}"
      endpoints                   = { s3 = "https://s3.${REGION}.scw.cloud" }
      encrypt                     = true # Server-side encryption of the state and lock files
      use_path_style              = true
      skip_credentials_validation = true
      skip_region_validation      = true
      skip_requesting_account_id  = true
      use_lockfile                = true # State locking
    }
  }
EOF
}

main() {
  parse_args "$@"
  check_dependencies
  resolve_credentials
  resolve_region
  derive_names
  check_secret_location
  confirm

  ensure_project
  ensure_bucket
  ensure_application
  ensure_admin_membership
  ensure_secret
  ensure_api_key

  summary
}

main "$@"
