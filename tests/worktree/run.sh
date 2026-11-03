#!/usr/bin/env bash
# tests/worktree/run.sh — regression suite for the v1.4 worktree isolation
# tooling: link-deps.sh (manifest parsing + symlinking) and gate-lock.sh
# (take-turns serialization), plus install integration.
#
# Sourced contract: uses record_pass/record_fail/record_skip from
# tests/helpers/assert.sh; never exit-s (the orchestrator owns the exit code).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/../.." && pwd)"
LINK_DEPS="${REPO}/shell/worktree/link-deps.sh"
GATE_LOCK="${REPO}/shell/worktree/gate-lock.sh"

# shellcheck disable=SC1091
source "${REPO}/tests/helpers/assert.sh"

# Must come AFTER the source above — deploy_source_repo lives in assert.sh.
# Files under test stay at ${REPO} (this checkout's copies); the DEPLOYED
# symlink targets are main's paths, since v1.25 install.sh always deploys from
# the main checkout whichever worktree invokes it.
_DEPLOY_SRC="$(deploy_source_repo "${REPO}")"
LINK_DEPS_DEPLOYED="${_DEPLOY_SRC}/shell/worktree/link-deps.sh"
GATE_LOCK_DEPLOYED="${_DEPLOY_SRC}/shell/worktree/gate-lock.sh"

# --- syntax (these scripts live under shell/, which the gate's syntax loop
#     does not walk, so cover them here) ---
if bash -n "${LINK_DEPS}" 2>/dev/null; then
    record_pass "worktree: link-deps.sh bash syntax clean"
else
    record_fail "worktree: link-deps.sh bash syntax"
fi
if bash -n "${GATE_LOCK}" 2>/dev/null; then
    record_pass "worktree: gate-lock.sh bash syntax clean"
else
    record_fail "worktree: gate-lock.sh bash syntax"
fi

# --- Test 1: link-deps links a present path ---
tmp1="$(mktemp -d)"; trap 'rm -rf "${tmp1}"' EXIT
mkdir -p "${tmp1}/main/.claude" "${tmp1}/wt"
printf '.env\n' > "${tmp1}/main/.claude/worktree-deps"
echo "SECRET=1" > "${tmp1}/main/.env"
out="$(bash "${LINK_DEPS}" "${tmp1}/main" "${tmp1}/wt" 2>&1)"; rc=$?
if [[ ${rc} -eq 0 && -L "${tmp1}/wt/.env" && "$(readlink "${tmp1}/wt/.env")" == "${tmp1}/main/.env" ]]; then
    record_pass "worktree: link-deps links a present path as a symlink"
else
    record_fail "worktree: link-deps present path (rc=${rc}, out: ${out})"
fi

# --- Test 2: link-deps warns + continues on a missing source ---
tmp2="$(mktemp -d)"; trap 'rm -rf "${tmp1}" "${tmp2}"' EXIT
mkdir -p "${tmp2}/main/.claude" "${tmp2}/wt"
printf 'frontend/node_modules\n' > "${tmp2}/main/.claude/worktree-deps"
out="$(bash "${LINK_DEPS}" "${tmp2}/main" "${tmp2}/wt" 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "WARN source missing, skipped: frontend/node_modules"; then
    record_pass "worktree: link-deps warns and exits 0 on missing source"
else
    record_fail "worktree: link-deps missing source (rc=${rc}, out: ${out})"
fi

# --- Test 3: link-deps ignores comment + blank lines ---
tmp3="$(mktemp -d)"; trap 'rm -rf "${tmp1}" "${tmp2}" "${tmp3}"' EXIT
mkdir -p "${tmp3}/main/.claude" "${tmp3}/wt"
printf '# a comment\n\n.env\n' > "${tmp3}/main/.claude/worktree-deps"
echo "x" > "${tmp3}/main/.env"
out="$(bash "${LINK_DEPS}" "${tmp3}/main" "${tmp3}/wt" 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "1 linked, 0 missing"; then
    record_pass "worktree: link-deps ignores comments and blank lines"
else
    record_fail "worktree: link-deps comment/blank handling (rc=${rc}, out: ${out})"
fi

# --- Test 4: link-deps no-op without a manifest ---
tmp4="$(mktemp -d)"; trap 'rm -rf "${tmp1}" "${tmp2}" "${tmp3}" "${tmp4}"' EXIT
mkdir -p "${tmp4}/main" "${tmp4}/wt"
out="$(bash "${LINK_DEPS}" "${tmp4}/main" "${tmp4}/wt" 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && echo "${out}" | grep -q "nothing to link"; then
    record_pass "worktree: link-deps no-ops without a manifest"
else
    record_fail "worktree: link-deps no-manifest (rc=${rc}, out: ${out})"
fi

# --- Tests 4b-4g: link-deps derives its own paths (no-argument form) ---
# /plan and /code invoke link-deps.sh with NO arguments, because a
# worktree-isolated session's command guard refuses any command containing a
# variable or substitution — "${MAIN}", "$(pwd)", "${PWD}" all trip it, so the
# old two-argument invocation was refused outright and the linking step silently
# never ran. These assertions pin the derivation that makes the literal form
# possible. The two-argument form stays supported (Tests 1-4 above use it).
tmp4b="$(mktemp -d)"
trap 'rm -rf "${tmp1}" "${tmp2}" "${tmp3}" "${tmp4}" "${tmp4b}"' EXIT

PROJ="${tmp4b}/proj"
mkdir -p "${PROJ}/.claude" "${PROJ}/node_modules/pkg"
git init -q "${PROJ}"
git -C "${PROJ}" config user.email t@t
git -C "${PROJ}" config user.name t
printf '.env\nnode_modules\n' > "${PROJ}/.claude/worktree-deps"
printf 'SECRET=1\n' > "${PROJ}/.env"
: > "${PROJ}/README.md"
git -C "${PROJ}" add -A >/dev/null 2>&1
git -C "${PROJ}" commit -qm init >/dev/null 2>&1

if git -C "${PROJ}" worktree add -q "${PROJ}/.claude/worktrees/feat" -b feat 2>/dev/null; then
    WTDIR="${PROJ}/.claude/worktrees/feat"

    # 4b. No arguments, run from inside the worktree: derives both paths and
    #     links the manifest's entries into the worktree.
    out="$( cd "${WTDIR}" && bash "${LINK_DEPS}" 2>&1 )"; rc=$?
    if [[ ${rc} -eq 0 ]] && grep -q "2 linked, 0 missing" <<<"${out}"; then
        record_pass "worktree: link-deps with NO arguments derives both paths and links"
    else
        record_fail "worktree: link-deps no-arg derivation (rc=${rc}, out: ${out})"
    fi

    # 4c. The links point at the MAIN checkout, not anywhere else — the
    #     derivation being right, not merely non-crashing.
    if [[ -L "${WTDIR}/.env" && "$(readlink "${WTDIR}/.env")" == "${PROJ}/.env" ]] \
        && [[ -L "${WTDIR}/node_modules" ]]; then
        record_pass "worktree: no-arg links resolve to the main checkout"
    else
        record_fail "worktree: no-arg link targets (.env -> $(readlink "${WTDIR}/.env" 2>&1))"
    fi

    # 4d. SELF-LINK GUARD. Run from the MAIN checkout, toplevel and common-dir
    #     parent are the same path, so an unguarded run would do
    #     `ln -sfn "${PROJ}/.env" "${PROJ}/.env"` — replacing a real file with a
    #     symlink to itself. Destructive and silent until the app cannot read
    #     its own config. Assert the refusal AND that .env survived intact.
    out="$( cd "${PROJ}" && bash "${LINK_DEPS}" 2>&1 )"; rc=$?
    if [[ ${rc} -eq 2 ]] && grep -q "same directory" <<<"${out}" \
        && [[ ! -L "${PROJ}/.env" && "$(cat "${PROJ}/.env")" == "SECRET=1" ]]; then
        record_pass "worktree: link-deps refuses to link a checkout to itself (real file intact)"
    else
        record_fail "worktree: self-link guard (rc=${rc}, .env is $( [[ -L ${PROJ}/.env ]] && echo SYMLINK || echo file), out: ${out})"
    fi
else
    record_skip "worktree: link-deps no-arg derivation (git worktree add failed)"
fi

# 4e. One argument is ambiguous — reject rather than guess the other path.
out="$(bash "${LINK_DEPS}" "${tmp4b}" 2>&1)"; rc=$?
if [[ ${rc} -eq 2 ]] && grep -q "expected 0 or 2 arguments" <<<"${out}"; then
    record_pass "worktree: link-deps rejects a single argument"
else
    record_fail "worktree: single-arg rejection (rc=${rc}, out: ${out})"
fi

# 4f. No arguments outside a git repo: a clean error, never a silent link into
#     whatever directory happens to be current.
nogit="${tmp4b}/nogit"; mkdir -p "${nogit}"
out="$( cd "${nogit}" && GIT_CEILING_DIRECTORIES="${tmp4b}" bash "${LINK_DEPS}" 2>&1 )"; rc=$?
if [[ ${rc} -eq 2 ]] && grep -q "not inside a git repository" <<<"${out}"; then
    record_pass "worktree: link-deps outside a git repo exits 2 with a clear error"
else
    record_fail "worktree: non-repo case (rc=${rc}, out: ${out})"
fi

# 4g. --help exits 0 and documents both forms.
out="$(bash "${LINK_DEPS}" --help 2>&1)"; rc=$?
if [[ ${rc} -eq 0 ]] && grep -q "derives both paths itself" <<<"${out}"; then
    record_pass "worktree: link-deps --help documents the no-argument form"
else
    record_fail "worktree: --help (rc=${rc})"
fi

# Clean tmp4b explicitly: the traps set by Tests 5+ below replace this one and
# do NOT list tmp4b, so relying on the trap alone would leak a directory — and
# this one holds a registered git worktree, not just files. The trap above still
# covers a hard crash mid-block.
rm -rf "${tmp4b}"

# --- Test 5: gate-lock runs the wrapped command ---
tmp5="$(mktemp -d)"; trap 'rm -rf "${tmp1}" "${tmp2}" "${tmp3}" "${tmp4}" "${tmp5}"' EXIT
(
    cd "${tmp5}" && git init -q
    # shellcheck disable=SC1090
    source "${GATE_LOCK}"
    with_gate_lock true
) && record_pass "worktree: with_gate_lock runs the wrapped command (exit 0)" \
  || record_fail "worktree: with_gate_lock failed to run wrapped command"

# --- Test 6: gate-lock serializes two concurrent calls ---
if command -v flock >/dev/null 2>&1; then
    tmp6="$(mktemp -d)"; trap 'rm -rf "${tmp1}" "${tmp2}" "${tmp3}" "${tmp4}" "${tmp5}" "${tmp6}"' EXIT
    (
        cd "${tmp6}" && git init -q
        # shellcheck disable=SC1090
        source "${GATE_LOCK}"
        order="${tmp6}/order"
        : > "${order}"
        # A grabs the lock first (small head start), holds it ~0.3s.
        with_gate_lock bash -c "echo A-start >> '${order}'; sleep 0.3; echo A-end >> '${order}'" &
        sleep 0.1
        with_gate_lock bash -c "echo B-start >> '${order}'; echo B-end >> '${order}'" &
        wait
        # No interleave: lines 1-2 are one actor, lines 3-4 the other.
        l1="$(sed -n 1p "${order}" | cut -d- -f1)"
        l2="$(sed -n 2p "${order}" | cut -d- -f1)"
        l3="$(sed -n 3p "${order}" | cut -d- -f1)"
        l4="$(sed -n 4p "${order}" | cut -d- -f1)"
        [[ "${l1}" == "${l2}" && "${l3}" == "${l4}" && "${l1}" != "${l3}" ]]
    ) && record_pass "worktree: with_gate_lock serializes concurrent runs (no interleave)" \
      || record_fail "worktree: with_gate_lock did NOT serialize (interleaved)"
else
    record_skip "worktree: gate-lock serialization (flock not installed)"
fi

# --- Tests 6b-6i: v1.22 acquire/release API + contention visibility ---
# The lock used to block in total silence, which made a queued gate look hung.
# These cover the messaging as well as the locking, because "silent when
# uncontended" is a property a later change breaks without anyone noticing.
if command -v flock >/dev/null 2>&1; then
    tmp6b="$(mktemp -d)"
    trap 'rm -rf "${tmp1}" "${tmp2}" "${tmp3}" "${tmp4}" "${tmp5}" "${tmp6:-}" "${tmp6b}"' EXIT
    git init -q "${tmp6b}"
    HOLDER_FILE="${tmp6b}/.git/gate.lock.holder"

    # 6b. Uncontended acquire/release is silent. A message on every gate run is
    #     noise, and noise on the common path is how a real warning gets ignored.
    out="$( { cd "${tmp6b}" && source "${GATE_LOCK}" && gate_lock_acquire quiet \
              && gate_lock_release; } 2>&1 )"
    if [[ -z "${out}" ]]; then
        record_pass "worktree: gate_lock_acquire is silent when uncontended"
    else
        record_fail "worktree: uncontended acquire printed '${out}'"
    fi

    # Hold the lock in the background for the contention checks below.
    ( cd "${tmp6b}" && source "${GATE_LOCK}" && gate_lock_acquire holder \
        && sleep 3 && gate_lock_release ) >/dev/null 2>&1 &
    _holder_job=$!
    sleep 1

    # 6c. The holder file names the live holder while the lock is held.
    if [[ -r "${HOLDER_FILE}" ]] && grep -q "^pid=[0-9]" "${HOLDER_FILE}"; then
        record_pass "worktree: holder file records the lock holder's pid"
    else
        record_fail "worktree: holder file missing/malformed ($(cat "${HOLDER_FILE}" 2>&1))"
    fi

    # 6d + 6e. A contended acquire announces the wait naming the holder, and
    #     reports how long it waited once it gets in.
    wout="$( { cd "${tmp6b}" && source "${GATE_LOCK}" && gate_lock_acquire waiter \
               && gate_lock_release; } 2>&1 )"
    if grep -q "waiting for another session" <<<"${wout}" \
        && grep -qE "held by pid [0-9]+" <<<"${wout}"; then
        record_pass "worktree: contended acquire announces the wait and names the holder"
    else
        record_fail "worktree: contention announcement (out: ${wout})"
    fi
    if grep -qE "acquired after [0-9]+s" <<<"${wout}"; then
        record_pass "worktree: acquiring after a wait reports how long it waited"
    else
        record_fail "worktree: acquired-after line (out: ${wout})"
    fi
    wait "${_holder_job}" 2>/dev/null || true

    # 6f. Release clears the holder file.
    if [[ ! -e "${HOLDER_FILE}" ]]; then
        record_pass "worktree: gate_lock_release clears the holder file"
    else
        record_fail "worktree: holder file survived release"
    fi

    # 6g. Release without a prior acquire exits 0, and repeats are no-ops.
    #     Consumers call release from early-exit paths that never took the lock.
    if ( cd "${tmp6b}" && source "${GATE_LOCK}" && gate_lock_release \
         && gate_lock_release && gate_lock_acquire x && gate_lock_release \
         && gate_lock_release ) >/dev/null 2>&1; then
        record_pass "worktree: gate_lock_release is safe without acquire and when repeated"
    else
        record_fail "worktree: gate_lock_release on an unheld lock did not exit 0"
    fi

    # 6h. A stale holder file — a pid that is gone — must not block acquisition,
    #     and must not be reported as a live holder. flock releases on death, so
    #     the file routinely outlives its process.
    printf 'pid=999999 started=2020-01-01T00:00:00 label=stale\n' > "${HOLDER_FILE}"
    sout="$( { cd "${tmp6b}" && source "${GATE_LOCK}" && gate_lock_acquire fresh \
               && gate_lock_release; } 2>&1 )"
    if [[ -z "${sout}" ]] && ! grep -q "999999" <<<"${sout}"; then
        record_pass "worktree: a stale holder file neither blocks nor is reported as live"
    else
        record_fail "worktree: stale holder handling (out: ${sout})"
    fi

    # 6i. The new API serializes, same no-interleave technique as Test 6.
    (
        cd "${tmp6b}" || exit 1
        # shellcheck disable=SC1090
        source "${GATE_LOCK}"
        order="${tmp6b}/order"; : > "${order}"
        ( gate_lock_acquire A; echo A-start >> "${order}"; sleep 0.3
          echo A-end >> "${order}"; gate_lock_release ) &
        sleep 0.1
        ( gate_lock_acquire B; echo B-start >> "${order}"; echo B-end >> "${order}"
          gate_lock_release ) &
        wait
        l1="$(sed -n 1p "${order}" | cut -d- -f1)"
        l2="$(sed -n 2p "${order}" | cut -d- -f1)"
        l3="$(sed -n 3p "${order}" | cut -d- -f1)"
        l4="$(sed -n 4p "${order}" | cut -d- -f1)"
        [[ "${l1}" == "${l2}" && "${l3}" == "${l4}" && "${l1}" != "${l3}" ]]
    ) && record_pass "worktree: gate_lock_acquire/release serializes (no interleave)" \
      || record_fail "worktree: gate_lock_acquire/release did NOT serialize"

    # Clean tmp6b explicitly: the Test 7 trap below replaces this block's trap
    # and does not list tmp6b, so it leaked one directory per gate run from
    # v1.22 until this was noticed (43 had accumulated in /tmp). Same shape as
    # the tmp4b cleanup above — when a suite chains traps, a block that adds a
    # temp dir must remove it before the next trap drops it.
    rm -rf "${tmp6b}"
else
    record_skip "worktree: gate_lock_acquire/release contention tests (flock not installed)"
fi

# --- Test 6p: gate_lock_holder_alive — the read-only "is a gate running" probe
# (v1.47, issue #140). Notes are written by hand in the exact format
# _gate_lock_stamp writes. Every call runs from / with the repo passed as an
# argument, the way a cron job or systemd unit would call it. tmp6p is removed
# explicitly at the end of the block (a later trap replaces this one — see the
# tmp6b note above).
tmp6p="$(mktemp -d)"
git init -q "${tmp6p}/repo"
git -C "${tmp6p}/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
P_HOLDER="${tmp6p}/repo/.git/gate.lock.holder"
P_LOCK="${tmp6p}/repo/.git/gate.lock"
sleep 120 &
P_LIVE=$!

# A `date` shim that answers `date -d ""` with NOW. Real `date -d ""` is midnight
# today, which is "recent" only between 00:00 and 02:00 — so without the shim the
# empty-started check would pass or fail depending on the time of day.
mkdir -p "${tmp6p}/shim"
cat > "${tmp6p}/shim/date" <<'SHIM'
#!/usr/bin/env bash
if [[ "${1:-}" == "-d" && -z "${2:-}" ]]; then exec /bin/date +%s; fi
exec /bin/date "$@"
SHIM
chmod +x "${tmp6p}/shim/date"

_p_note() { printf 'pid=%s started=%s label=%s\n' "$1" "$2" "$3" > "${P_HOLDER}"; }
_p_ts()   { date -d "$1" '+%Y-%m-%dT%H:%M:%S'; }
# _p_probe <args...> -> sets POUT (stdout), PERR (stderr), PRC
_p_probe() {
    local errf="${tmp6p}/err"
    POUT="$( cd / && PATH="${tmp6p}/shim:${PATH}" bash -c 'source "$1"; shift; gate_lock_holder_alive "$@"' _ "${GATE_LOCK}" "$@" 2>"${errf}" )"
    PRC=$?
    PERR="$(cat "${errf}")"
}

# 6j. Live pid, recent note, label with a space -> exit 0 and the exact line.
TS_NOW="$(_p_ts 'now')"
_p_note "${P_LIVE}" "${TS_NOW}" "gate fast"
_p_probe "${tmp6p}/repo"
if [[ ${PRC} -eq 0 && "${POUT}" == "pid=${P_LIVE} label=gate fast started=${TS_NOW}" ]]; then
    record_pass "worktree: gate_lock_holder_alive reports a live recent holder (exit 0, exact line)"
else
    record_fail "worktree: gate_lock_holder_alive live holder — rc=${PRC}, out=${POUT}"
fi

# 6k. Dead pid -> exit 1, no output (a killed gate leaves its note behind).
_p_note 999999 "${TS_NOW}" "gate fast"
_p_probe "${tmp6p}/repo"
if [[ ${PRC} -eq 1 && -z "${POUT}" ]]; then
    record_pass "worktree: gate_lock_holder_alive ignores a dead pid"
else
    record_fail "worktree: gate_lock_holder_alive dead pid — rc=${PRC}, out=${POUT}"
fi

# 6l. Missing note -> exit 1.
rm -f "${P_HOLDER}"
_p_probe "${tmp6p}/repo"
if [[ ${PRC} -eq 1 && -z "${POUT}" ]]; then
    record_pass "worktree: gate_lock_holder_alive returns 1 with no holder note"
else
    record_fail "worktree: gate_lock_holder_alive no note — rc=${PRC}, out=${POUT}"
fi

# 6m. Empty started= -> exit 1 (clock-independent via the date shim).
_p_note "${P_LIVE}" "" "x"
_p_probe "${tmp6p}/repo"
if [[ ${PRC} -eq 1 && -z "${POUT}" ]]; then
    record_pass "worktree: gate_lock_holder_alive ignores an empty started= (not treated as recent)"
else
    record_fail "worktree: gate_lock_holder_alive empty started — rc=${PRC}, out=${POUT}"
fi

# 6n. Unparseable started= -> exit 1.
_p_note "${P_LIVE}" "garbage" "x"
_p_probe "${tmp6p}/repo"
if [[ ${PRC} -eq 1 && -z "${POUT}" ]]; then
    record_pass "worktree: gate_lock_holder_alive ignores an unparseable started="
else
    record_fail "worktree: gate_lock_holder_alive garbage started — rc=${PRC}, out=${POUT}"
fi

# 6o. Older than the limit -> exit 1; a bigger limit accepts the same note.
TS_OLD="$(_p_ts '3 hours ago')"
_p_note "${P_LIVE}" "${TS_OLD}" "hung"
_p_probe "${tmp6p}/repo"
old_rc=${PRC}
_p_probe "${tmp6p}/repo" 240
if [[ ${old_rc} -eq 1 && ${PRC} -eq 0 ]]; then
    record_pass "worktree: gate_lock_holder_alive honours the age limit (default 120, overridable)"
else
    record_fail "worktree: gate_lock_holder_alive age limit — default rc=${old_rc}, 240 rc=${PRC}"
fi

# 6p. A note stamped in the future (clock change) is not older than the limit.
_p_note "${P_LIVE}" "$(_p_ts '1 hour')" "skew"
_p_probe "${tmp6p}/repo"
if [[ ${PRC} -eq 0 ]]; then
    record_pass "worktree: gate_lock_holder_alive accepts a future-stamped note"
else
    record_fail "worktree: gate_lock_holder_alive future note — rc=${PRC}, out=${POUT}"
fi

# 6q. Bad max-age-minutes -> exit 2 with a message; "08" is decimal, not octal.
_p_note "${P_LIVE}" "${TS_NOW}" "x"
bad_ok=1
for bad in abc -5 1.5; do
    _p_probe "${tmp6p}/repo" "${bad}"
    [[ ${PRC} -eq 2 && -z "${POUT}" && -n "${PERR}" ]] || bad_ok=0
done
_p_probe "${tmp6p}/repo" 08
if [[ ${bad_ok} -eq 1 && ${PRC} -eq 0 ]]; then
    record_pass "worktree: gate_lock_holder_alive rejects a bad limit (exit 2); 08 is read as decimal"
else
    record_fail "worktree: gate_lock_holder_alive limit handling — bad_ok=${bad_ok}, 08 rc=${PRC} (${PERR})"
fi

# 6r. Works from a linked worktree via repo-dir (shared git common dir) ...
git -C "${tmp6p}/repo" worktree add -q "${tmp6p}/wt" -b probe-wt
_p_note "${P_LIVE}" "${TS_NOW}" "gate fast"
_p_probe "${tmp6p}/wt"
wt_rc=${PRC}; wt_out="${POUT}"
# ... and with no argument from inside the repo.
POUT="$( cd "${tmp6p}/repo" && bash -c 'source "$1"; gate_lock_holder_alive' _ "${GATE_LOCK}" 2>/dev/null )"
noarg_rc=$?
if [[ ${wt_rc} -eq 0 && "${wt_out}" == "pid=${P_LIVE} label=gate fast started=${TS_NOW}" \
      && ${noarg_rc} -eq 0 && "${POUT}" == "${wt_out}" ]]; then
    record_pass "worktree: gate_lock_holder_alive works from a linked worktree and with no argument"
else
    record_fail "worktree: gate_lock_holder_alive worktree/no-arg — wt rc=${wt_rc} (${wt_out}), noarg rc=${noarg_rc} (${POUT})"
fi

# 6s. A directory that is not a git repo -> exit 1, and nothing is created in it.
mkdir "${tmp6p}/nongit"
if [[ -e /tmp/gate.lock.holder ]]; then
    record_skip "worktree: gate_lock_holder_alive non-git dir (a real /tmp/gate.lock.holder exists)"
else
    _p_probe "${tmp6p}/nongit"
    if [[ ${PRC} -eq 1 && -z "$(ls -A "${tmp6p}/nongit")" ]]; then
        record_pass "worktree: gate_lock_holder_alive on a non-git dir returns 1 and creates nothing"
    else
        record_fail "worktree: gate_lock_holder_alive non-git dir — rc=${PRC}, contents=$(ls -A "${tmp6p}/nongit")"
    fi
fi

# 6t. Never touches gate.lock: a successful probe does not create it ...
rm -f "${P_LOCK}"
_p_note "${P_LIVE}" "${TS_NOW}" "x"
_p_probe "${tmp6p}/repo"
if [[ ${PRC} -eq 0 && ! -e "${P_LOCK}" ]]; then
    record_pass "worktree: gate_lock_holder_alive does not create gate.lock"
else
    record_fail "worktree: gate_lock_holder_alive created/needed gate.lock — rc=${PRC}, lock exists: $([[ -e "${P_LOCK}" ]] && echo yes || echo no)"
fi

# 6u. ... and while a real gate HOLDS the lock it answers at once, names the
# holder, and leaves the lock held.
if command -v flock >/dev/null 2>&1; then
    ( cd "${tmp6p}/repo" && source "${GATE_LOCK}" && gate_lock_acquire held \
        && sleep 4 && gate_lock_release ) >/dev/null 2>&1 &
    held_job=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        grep -q 'label=held' "${P_HOLDER}" 2>/dev/null && break
        sleep 0.3
    done
    SECONDS=0
    _p_probe "${tmp6p}/repo"
    probe_secs=${SECONDS}
    ( flock -n 9 ) 9>>"${P_LOCK}" 2>/dev/null; still_held=$?
    if [[ ${PRC} -eq 0 && "${POUT}" == *"label=held"* && ${probe_secs} -lt 2 && ${still_held} -ne 0 ]]; then
        record_pass "worktree: gate_lock_holder_alive answers at once while a gate holds the lock, and does not take it"
    else
        record_fail "worktree: gate_lock_holder_alive under a held lock — rc=${PRC}, out=${POUT}, secs=${probe_secs}, lock_still_held_rc=${still_held}"
    fi
    wait "${held_job}" 2>/dev/null || true
else
    record_skip "worktree: gate_lock_holder_alive under a held lock (flock not installed)"
fi

# 6v. Regression: _gate_lock_describe_holder (now reading through the shared
# field parser) still says "pid N (since S)" for a live holder, "another session"
# for a dead one.
_p_note "${P_LIVE}" "${TS_NOW}" "x"
desc_live="$( cd "${tmp6p}/repo" && bash -c 'source "$1"; _gate_lock_describe_holder' _ "${GATE_LOCK}" )"
_p_note 999999 "${TS_NOW}" "x"
desc_dead="$( cd "${tmp6p}/repo" && bash -c 'source "$1"; _gate_lock_describe_holder' _ "${GATE_LOCK}" )"
if [[ "${desc_live}" == "pid ${P_LIVE} (since ${TS_NOW})" && "${desc_dead}" == "another session" ]]; then
    record_pass "worktree: _gate_lock_describe_holder unchanged after the parser extraction"
else
    record_fail "worktree: _gate_lock_describe_holder — live='${desc_live}', dead='${desc_dead}'"
fi

kill "${P_LIVE}" 2>/dev/null || true
wait "${P_LIVE}" 2>/dev/null || true
rm -rf "${tmp6p}"

# --- Test 7: install integration (tmpdir HOME) ---
tmp7="$(mktemp -d)"; trap 'rm -rf "${tmp1}" "${tmp2}" "${tmp3}" "${tmp4}" "${tmp5}" "${tmp6:-}" "${tmp7}"' EXIT
HOME="${tmp7}" bash "${REPO}/scripts/install.sh" worktree >/dev/null 2>&1
ld="${tmp7}/.claude/worktree/link-deps.sh"
gl="${tmp7}/.claude/worktree/gate-lock.sh"
if [[ -L "${ld}" && "$(readlink "${ld}")" == "${LINK_DEPS_DEPLOYED}" \
   && -L "${gl}" && "$(readlink "${gl}")" == "${GATE_LOCK_DEPLOYED}" ]]; then
    record_pass "worktree: install deploys link-deps.sh + gate-lock.sh as symlinks"
else
    record_fail "worktree: install integration (ld=$(readlink "${ld}" 2>/dev/null), gl=$(readlink "${gl}" 2>/dev/null))"
fi
