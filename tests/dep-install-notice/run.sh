#!/usr/bin/env bash
# tests/dep-install-notice/run.sh — regression suite for
# scripts/check-dep-install-needed.sh (v1.48, dev-platform issue #151).
#
# Sourced contract: uses record_pass/record_fail/record_skip from
# tests/helpers/assert.sh; never exit-s (the orchestrator owns the exit code).
#
# Entirely offline. Every case builds a real throwaway git repo (git init, a
# baseline commit, then a change commit) so `git diff-tree` and
# `git rev-parse --git-common-dir` return genuine output. No package manager is
# ever run: check 15 puts fake npm/pnpm/yarn first on PATH and asserts they were
# never called.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
SCRIPT="${REPO}/scripts/check-dep-install-needed.sh"
LINK_DEPS="${REPO}/shell/worktree/link-deps.sh"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

TMP="$(mktemp -d /tmp/dep-notice.XXXXXX)"
trap 'rm -rf "${TMP}"' EXIT

# --- helpers -----------------------------------------------------------------

# mkrepo <name> <manifest-text|NONE> <file>... — a repo whose baseline commit
# holds every listed file. Prints the repo path.
mkrepo() {
    local name="$1" manifest="$2" d f
    shift 2
    d="${TMP}/${name}"
    mkdir -p "${d}"
    git -C "${d}" init -q -b main
    git -C "${d}" config user.email t@t
    git -C "${d}" config user.name t
    if [[ "${manifest}" != "NONE" ]]; then
        mkdir -p "${d}/.claude"
        printf '%s\n' "${manifest}" > "${d}/.claude/worktree-deps"
    fi
    for f in "$@"; do
        mkdir -p "$(dirname "${d}/${f}")"
        echo base > "${d}/${f}"
    done
    git -C "${d}" add -A
    git -C "${d}" commit -q -m base
    printf '%s' "${d}"
}

# change <repo> <file>... — one commit that modifies (or creates) the files.
change() {
    local d="$1" f
    shift
    for f in "$@"; do
        mkdir -p "$(dirname "${d}/${f}")"
        echo "${RANDOM}${RANDOM}" >> "${d}/${f}"
    done
    git -C "${d}" add -A
    git -C "${d}" commit -q -m change
}

# run_notice <repo> [args...] -> sets OUT, ERR, RC. PATH_PREFIX, if set, is put
# in front of PATH for the run.
run_notice() {
    local repo="$1"
    shift
    OUT="$( cd "${repo}" && PATH="${PATH_PREFIX:+${PATH_PREFIX}:}${PATH}" bash "${SCRIPT}" "$@" 2>"${TMP}/err" )"
    RC=$?
    ERR="$(cat "${TMP}/err")"
}

has()  { [[ "${OUT}" == *"$1"* ]]; }
phys() { ( cd "$1" && pwd -P ); }

# --- 1-3. the basic notice, and the quiet cases ---------------------------------

FE_MANIFEST='frontend/node_modules'
FE_FILES=(frontend/package.json frontend/package-lock.json frontend/src/app.ts)

r1="$(mkrepo r1 "${FE_MANIFEST}" "${FE_FILES[@]}")"
change "${r1}" frontend/package-lock.json
run_notice "${r1}"
P1="$(phys "${r1}")"
if [[ ${RC} -eq 0 ]] && has "frontend/: package-lock.json" \
        && has "npm --prefix ${P1}/frontend install" && has "restart"; then
    record_pass "dep-install-notice: changed lock file beside a linked node_modules -> notice with dir, file, install command, restart"
else
    record_fail "dep-install-notice: basic notice wrong — rc=${RC}, out=${OUT:0:400}"
fi

r2="$(mkrepo r2 "${FE_MANIFEST}" "${FE_FILES[@]}")"
change "${r2}" frontend/package.json
run_notice "${r2}"
if [[ ${RC} -eq 0 ]] && has "frontend/: package.json" && ! has "package-lock"; then
    record_pass "dep-install-notice: package.json alone -> notice"
else
    record_fail "dep-install-notice: package.json-only case wrong — rc=${RC}, out=${OUT:0:300}"
fi

r3="$(mkrepo r3 "${FE_MANIFEST}" "${FE_FILES[@]}")"
change "${r3}" frontend/src/app.ts
run_notice "${r3}"
if [[ ${RC} -eq 0 && -z "${OUT}" && -z "${ERR}" ]]; then
    record_pass "dep-install-notice: unrelated change -> silent"
else
    record_fail "dep-install-notice: unrelated change not silent — rc=${RC}, out=${OUT:0:200}, err=${ERR:0:200}"
fi

# --- 4-6. nothing to watch -------------------------------------------------------

r4="$(mkrepo r4 NONE package-lock.json)"
change "${r4}" package-lock.json
run_notice "${r4}"
if [[ ${RC} -eq 0 && -z "${OUT}" ]]; then
    record_pass "dep-install-notice: no manifest -> silent"
else
    record_fail "dep-install-notice: no-manifest case wrong — rc=${RC}, out=${OUT:0:200}"
fi

r5="$(mkrepo r5 '# nothing is linked in this project' package-lock.json)"
change "${r5}" package-lock.json
run_notice "${r5}"
if [[ ${RC} -eq 0 && -z "${OUT}" ]]; then
    record_pass "dep-install-notice: comment-only manifest -> silent"
else
    record_fail "dep-install-notice: comment-only manifest wrong — rc=${RC}, out=${OUT:0:200}"
fi

r6="$(mkrepo r6 '.env' package-lock.json)"
change "${r6}" package-lock.json
run_notice "${r6}"
if [[ ${RC} -eq 0 && -z "${OUT}" ]]; then
    record_pass "dep-install-notice: manifest with no node_modules entry -> silent"
else
    record_fail "dep-install-notice: non-node_modules manifest wrong — rc=${RC}, out=${OUT:0:200}"
fi

# --- 7. several dependency directories (SQRL's shape) -----------------------------

SQRL_MANIFEST=$'node_modules\nserver/node_modules\ndispatch/node_modules'
SQRL_FILES=(package.json package-lock.json server/package.json server/package-lock.json server/yarn.lock dispatch/package.json)

r7a="$(mkrepo r7a "${SQRL_MANIFEST}" "${SQRL_FILES[@]}")"
change "${r7a}" server/package-lock.json
run_notice "${r7a}"
P7A="$(phys "${r7a}")"
if has "server/: package-lock.json" && ! has "(repo root)" && ! has "dispatch/" \
        && has "npm --prefix ${P7A}/server install"; then
    record_pass "dep-install-notice: change in one of several dependency dirs names only that dir"
else
    record_fail "dep-install-notice: SQRL-shape single-dir case wrong — out=${OUT:0:400}"
fi

r7b="$(mkrepo r7b "${SQRL_MANIFEST}" "${SQRL_FILES[@]}")"
change "${r7b}" package-lock.json dispatch/package.json
run_notice "${r7b}"
P7B="$(phys "${r7b}")"
if has "(repo root): package-lock.json" && has "dispatch/: package.json" && ! has "server/" \
        && has "npm --prefix ${P7B} install"; then
    record_pass "dep-install-notice: repo-root and nested dirs together -> both named, root install path has no extra segment"
else
    record_fail "dep-install-notice: SQRL-shape root+nested case wrong — out=${OUT:0:400}"
fi

# --- 8. which package manager's command is printed --------------------------------

r8a="$(mkrepo r8a 'app/node_modules' app/package.json app/pnpm-lock.yaml)"
change "${r8a}" app/pnpm-lock.yaml
run_notice "${r8a}"; out8a="${OUT}"; P8A="$(phys "${r8a}")"
r8b="$(mkrepo r8b 'app/node_modules' app/package.json app/yarn.lock)"
change "${r8b}" app/yarn.lock
run_notice "${r8b}"; out8b="${OUT}"; P8B="$(phys "${r8b}")"
r8c="$(mkrepo r8c 'app/node_modules' app/package.json app/package-lock.json app/yarn.lock)"
change "${r8c}" app/yarn.lock
run_notice "${r8c}"; out8c="${OUT}"; P8C="$(phys "${r8c}")"
r8d="$(mkrepo r8d 'app/node_modules' app/package.json)"
change "${r8d}" app/package.json
run_notice "${r8d}"; out8d="${OUT}"; P8D="$(phys "${r8d}")"
if [[ "${out8a}" == *"pnpm --dir ${P8A}/app install"* \
   && "${out8b}" == *"yarn --cwd ${P8B}/app install"* \
   && "${out8c}" == *"npm --prefix ${P8C}/app install"* \
   && "${out8d}" == *"npm --prefix ${P8D}/app install"* ]]; then
    record_pass "dep-install-notice: install command follows the lock file (pnpm / yarn / npm wins over yarn / npm default)"
else
    record_fail "dep-install-notice: package manager choice wrong — pnpm='${out8a: -90}' yarn='${out8b: -90}' both='${out8c: -90}' none='${out8d: -90}'"
fi

# --- 9-10. manifest parsing, and parity with link-deps.sh --------------------------

MESSY_MANIFEST=$'# a comment line\nfrontend/node_modules   # inline comment\n   server/node_modules   \n\nnode_modules\n.env\ndispatch/node_modules/'
MESSY_FILES=(frontend/package.json server/package.json dispatch/package.json package.json)

r9="$(mkrepo r9 "${MESSY_MANIFEST}" "${MESSY_FILES[@]}")"
change "${r9}" frontend/package.json server/package.json dispatch/package.json package.json
run_notice "${r9}"
if has "frontend/: package.json" && has "server/: package.json" && has "(repo root): package.json" \
        && has "dispatch/: package.json"; then
    record_pass "dep-install-notice: messy manifest parsed (comments, whitespace, blanks, trailing slash)"
else
    record_fail "dep-install-notice: messy manifest wrong — out=${OUT:0:500}"
fi

# Parity: the set of node_modules link-deps.sh actually links must equal the set
# of dependency directories the notice script recognised for the same manifest.
mkdir -p "${r9}/frontend/node_modules" "${r9}/server/node_modules" "${r9}/dispatch/node_modules" "${r9}/node_modules"
: > "${r9}/.env"
wt9="${TMP}/r9-wt"
mkdir -p "${wt9}"
bash "${LINK_DEPS}" "${r9}" "${wt9}" >/dev/null 2>&1
linked=""
for entry in "frontend:frontend/node_modules" "server:server/node_modules" "dispatch:dispatch/node_modules" "root:node_modules"; do
    if [[ -L "${wt9}/${entry#*:}" ]]; then linked="${linked} ${entry%%:*}"; fi
done
recognised=""
for entry in "frontend:frontend/:" "server:server/:" "dispatch:dispatch/:" "root:(repo root):"; do
    if has "${entry#*:}"; then recognised="${recognised} ${entry%%:*}"; fi
done
if [[ -n "${linked}" && "${linked}" == "${recognised}" ]]; then
    record_pass "dep-install-notice: parity with link-deps.sh — both agree on which node_modules entries count (${linked# })"
else
    record_fail "dep-install-notice: parity broken — link-deps linked [${linked# }], notice recognised [${recognised# }]"
fi

# --- 11. the commit argument -------------------------------------------------------

r11="$(mkrepo r11 "${FE_MANIFEST}" frontend/package-lock.json other.txt)"
change "${r11}" frontend/package-lock.json
SHA_A="$(git -C "${r11}" rev-parse HEAD)"
change "${r11}" other.txt
run_notice "${r11}"
head_out="${OUT}"
run_notice "${r11}" "${SHA_A}"
if [[ -z "${head_out}" ]] && has "frontend/: package-lock.json"; then
    record_pass "dep-install-notice: commit argument selects the commit scanned (HEAD silent, older dependency commit reports)"
else
    record_fail "dep-install-notice: commit argument wrong — head='${head_out:0:100}', sha out='${OUT:0:200}'"
fi
run_notice "${r11}" no-such-revision
if [[ ${RC} -eq 0 && -z "${OUT}" ]]; then
    record_pass "dep-install-notice: invalid commit -> silent, exit 0"
else
    record_fail "dep-install-notice: invalid commit wrong — rc=${RC}, out=${OUT:0:200}"
fi

# --- 12-13. edges ------------------------------------------------------------------

r12="$(mkrepo r12 "${FE_MANIFEST}" frontend/package-lock.json)"
run_notice "${r12}"
if [[ ${RC} -eq 0 && -z "${ERR}" ]]; then
    record_pass "dep-install-notice: a repo with a single (root) commit runs cleanly"
else
    record_fail "dep-install-notice: first-commit case wrong — rc=${RC}, err=${ERR:0:200}"
fi

mkdir -p "${TMP}/plain"
run_notice "${TMP}/plain"
if [[ ${RC} -eq 0 && -z "${OUT}" ]]; then
    record_pass "dep-install-notice: outside a git repo -> silent, exit 0"
else
    record_fail "dep-install-notice: non-repo case wrong — rc=${RC}, out=${OUT:0:200}"
fi

# --- 14. run from a linked worktree --------------------------------------------------

r14="$(mkrepo r14 "${FE_MANIFEST}" "${FE_FILES[@]}")"
change "${r14}" frontend/package-lock.json
git -C "${r14}" worktree add -q "${TMP}/r14-wt" -b wt14
run_notice "${TMP}/r14-wt"
P14="$(phys "${r14}")"
if has "npm --prefix ${P14}/frontend install" && ! has "r14-wt"; then
    record_pass "dep-install-notice: from a linked worktree the install path is the MAIN checkout's"
else
    record_fail "dep-install-notice: worktree path wrong — out=${OUT:0:400}"
fi

# --- 15. never installs anything ------------------------------------------------------

mkdir -p "${TMP}/fakebin"
for pm in npm pnpm yarn; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "%s/pm.log"\n' "${pm}" "${TMP}" > "${TMP}/fakebin/${pm}"
    chmod +x "${TMP}/fakebin/${pm}"
done
rm -f "${TMP}/pm.log"
PATH_PREFIX="${TMP}/fakebin" run_notice "${r1}" HEAD
if [[ -n "${OUT}" && ! -s "${TMP}/pm.log" ]]; then
    record_pass "dep-install-notice: prints a notice but never runs npm, pnpm or yarn"
else
    record_fail "dep-install-notice: install safety wrong — out empty? $([[ -z "${OUT}" ]] && echo yes || echo no), pm.log: $(cat "${TMP}/pm.log" 2>/dev/null)"
fi

# --- 16. usage --------------------------------------------------------------------------

run_notice "${r1}" --help
help_rc=${RC}; help_out="${OUT}"
run_notice "${r1}" --bogus
bogus_rc=${RC}
run_notice "${r1}" HEAD HEAD
two_rc=${RC}
if [[ ${help_rc} -eq 0 && "${help_out}" == *"check-dep-install-needed"* && ${bogus_rc} -eq 2 && ${two_rc} -eq 2 ]]; then
    record_pass "dep-install-notice: --help exits 0; an unknown option and two arguments exit 2"
else
    record_fail "dep-install-notice: usage handling wrong — help=${help_rc}, bogus=${bogus_rc}, two=${two_rc}"
fi
