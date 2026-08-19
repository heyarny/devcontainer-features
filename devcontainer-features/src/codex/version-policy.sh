#!/usr/bin/env sh

# Source this file from feature wrappers, or execute it directly to validate one
# release. It intentionally contains only feature-owned policy and helpers.
# Do not set shell options here: a sourced library must not alter its caller's
# execution mode.
CODEX_FEATURE_MINIMUM_RELEASE="0.146.1"

codex_feature_normalize_release() {
    # OpenAI release identifiers may include the historical rust-v or v prefix;
    # policy comparisons use the numeric form.
    case "${1-}" in
        ""|latest)
            printf 'latest\n'
            ;;
        rust-v*)
            printf '%s\n' "${1#rust-v}"
            ;;
        v*)
            printf '%s\n' "${1#v}"
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

codex_feature_compare_decimal_component() {
    codex_feature_left="$1"
    codex_feature_right="$2"

    # Normalize leading zeroes, then compare digit counts before numeric values.
    # This makes decimal ordering independent of zero padding.
    while [ "${codex_feature_left#0}" != "${codex_feature_left}" ]; do
        codex_feature_left="${codex_feature_left#0}"
    done
    while [ "${codex_feature_right#0}" != "${codex_feature_right}" ]; do
        codex_feature_right="${codex_feature_right#0}"
    done
    codex_feature_left="${codex_feature_left:-0}"
    codex_feature_right="${codex_feature_right:-0}"

    if [ "${#codex_feature_left}" -lt "${#codex_feature_right}" ]; then
        printf '%s\n' -1
    elif [ "${#codex_feature_left}" -gt "${#codex_feature_right}" ]; then
        printf '%s\n' 1
    elif [ "${codex_feature_left}" = "${codex_feature_right}" ]; then
        printf '%s\n' 0
    elif [ "${codex_feature_left}" -lt "${codex_feature_right}" ]; then
        printf '%s\n' -1
    else
        printf '%s\n' 1
    fi
}

codex_feature_release_is_supported() {
    codex_feature_candidate="$1"
    codex_feature_candidate_core="${codex_feature_candidate%%-*}"
    codex_feature_minimum_core="${CODEX_FEATURE_MINIMUM_RELEASE%%-*}"

    # Split the already-validated numeric cores without relying on non-POSIX arrays.
    codex_feature_saved_ifs="${IFS}"
    IFS=.
    set -- ${codex_feature_candidate_core}
    IFS="${codex_feature_saved_ifs}"
    codex_feature_candidate_major="$1"
    codex_feature_candidate_minor="$2"
    codex_feature_candidate_patch="$3"

    codex_feature_saved_ifs="${IFS}"
    IFS=.
    set -- ${codex_feature_minimum_core}
    IFS="${codex_feature_saved_ifs}"
    codex_feature_minimum_major="$1"
    codex_feature_minimum_minor="$2"
    codex_feature_minimum_patch="$3"

    # Compare major, minor, and patch in order; the first difference decides.
    for codex_feature_pair in \
        "${codex_feature_candidate_major}:${codex_feature_minimum_major}" \
        "${codex_feature_candidate_minor}:${codex_feature_minimum_minor}" \
        "${codex_feature_candidate_patch}:${codex_feature_minimum_patch}"
    do
        codex_feature_comparison="$(
            codex_feature_compare_decimal_component \
                "${codex_feature_pair%%:*}" \
                "${codex_feature_pair#*:}"
        )"
        case "${codex_feature_comparison}" in
            -1)
                return 1
                ;;
            1)
                return 0
                ;;
        esac
    done

    # Equal numeric cores are supported only when the candidate is stable. A
    # prerelease of the minimum stable version still sorts below the minimum.
    case "${codex_feature_candidate}" in
        *-*) return 1 ;;
        *) return 0 ;;
    esac
}

codex_feature_validate_release() {
    codex_feature_requested_release="${1-}"
    codex_feature_normalized_release="$(
        codex_feature_normalize_release "${codex_feature_requested_release}"
    )"

    if [ "${codex_feature_normalized_release}" = "latest" ]; then
        return 0
    fi

    # Validate syntax before splitting fields so only three numeric components
    # and the prerelease forms published by Codex reach the comparator.
    if ! printf '%s\n' "${codex_feature_normalized_release}" |
        grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-alpha(\.[0-9]+){0,2}|-beta(\.[0-9]+)?)?$'
    then
        echo "Invalid Codex release version: ${codex_feature_normalized_release}. Expected latest or x.y.z[-alpha[.N[.M]]|-beta[.N]]." >&2
        return 1
    fi

    if ! codex_feature_release_is_supported "${codex_feature_normalized_release}"; then
        echo "Unsupported Codex release '${codex_feature_requested_release}'. Minimum supported release is ${CODEX_FEATURE_MINIMUM_RELEASE}; use 'latest' or a newer release." >&2
        return 1
    fi
}

codex_feature_version_policy_main() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: version-policy.sh RELEASE" >&2
        return 2
    fi

    codex_feature_validate_release "$1"
}

# Sourcing defines the helpers; direct execution provides a small validation CLI.
case "$0" in
    */version-policy.sh|version-policy.sh)
        codex_feature_version_policy_main "$@"
        exit $?
        ;;
esac
