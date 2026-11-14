#!/bin/bash
#
# Smoke test for dynmotd.sh inside a distribution container.
# Usage (as root, repository mounted at /src):  bash /src/.github/test.sh
#
# Every call must exit 0 and print nothing to stderr: an error message during
# a login is exactly what this script exists to catch. The outputs are kept in
# /src/.ci-out so the workflow can check them on the host.

set -u

script=/src/dynmotd.sh
out=/src/.ci-out
failed=0

rm -rf "$out"
mkdir -p "$out"

run() {
    local name="$1" rc
    shift
    "$@" > "${out}/${name}.out" 2> "${out}/${name}.err" < /dev/null
    rc=$?
    if [ "$rc" -ne 0 ] || [ -s "${out}/${name}.err" ]; then
        echo "FAIL ${name} (exit code ${rc})"
        sed 's/^/     | /' "${out}/${name}.err" | head -n 20
        failed=1
    else
        echo "ok   ${name}"
    fi
}

expect() {
    local what="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        echo "ok   ${what}"
    else
        echo "FAIL ${what}"
        failed=1
    fi
}

echo "image: ${IMAGE:-unknown}"
echo "bash:  ${BASH_VERSION}"
echo "awk:   $(readlink -f "$(command -v awk)" 2>/dev/null || command -v awk)"
echo

run syntax           bash -n "$script"
run version          bash "$script" --version
run genconfig        bash "$script" --genconfig
expect "config file created"         test -s /root/.dynmotd/dynmotd.conf
expect "config file is private"      test "$(stat -c %a /root/.dynmotd/dynmotd.conf)" = "600"

run motd             bash "$script"
expect "motd has a system section"   grep -q 'System Info' "${out}/motd.out"
expect "motd fits 79 columns"        sh -c "sed 's/\x1b\[[0-9;]*m//g' '${out}/motd.out' | awk 'length(\$0) > 79 { bad = 1 } END { exit bad }'"

run compact          bash "$script" --compact
run dashboard        env COLUMNS=200 LANG=C.UTF-8 bash "$script" --dashboard
run dashboard-ascii  env COLUMNS=100 LANG=C bash "$script" --dashboard
run json             bash "$script" --json
run check            bash "$script" --check
run help             bash "$script" --help

## Every section on its own
for section in $(bash "$script" --section 2>/dev/null | sed -n 's/^Sections: //p'); do
    run "section-${section}" bash "$script" --section "$section"
done

## All optional sections switched on: a missing tool must give a notice,
## never an error
sed -i 's/="auto"/="1"/' /root/.dynmotd/dynmotd.conf
run all-sections-on  bash "$script"
expect "missing tools give a notice" grep -q 'not installed (hide:' "${out}/all-sections-on.out"

## A broken configuration must be reported, not fatal
printf 'BOGUS="1"\nthis is not a setting\nDISK_WARN_PERCENT="abc"\nCOLOR_SCHEME="nope"\n' \
    >> /root/.dynmotd/dynmotd.conf
run broken-config    bash "$script"
expect "broken config is reported"   grep -q 'Problem' "${out}/broken-config.out"
run genconfig-repair bash "$script" --genconfig
run after-repair     bash "$script" --section config
expect "config is clean again"       test ! -s "${out}/after-repair.out"

## Maintenance log
run addlog           bash "$script" -a "ci test entry"
run listlog          bash "$script" -l
expect "log entry stored"            grep -q 'ci test entry' "${out}/listlog.out"
run rmlog            bash "$script" -d 1

## Update and uninstall. --install is not tested here: it installs packages,
## and the repositories of end-of-life distributions are gone.
mkdir -p /usr/local/bin /etc/profile.d
cp "$script" /usr/local/bin/dynmotd && chmod 755 /usr/local/bin/dynmotd
run update           bash "$script" --update
run installed        /usr/local/bin/dynmotd
expect "self-overwrite is refused"   sh -c '! /usr/local/bin/dynmotd --update'
expect "installed copy is intact"    cmp -s "$script" /usr/local/bin/dynmotd
printf '\n\n' | bash "$script" --uninstall > "${out}/uninstall.out" 2> "${out}/uninstall.err"
expect "uninstall removed the script"    test ! -e /usr/local/bin/dynmotd
expect "uninstall removed the data"      test ! -e /root/.dynmotd

echo
if [ "$failed" -ne 0 ]; then
    echo "FAILED"
    exit 1
fi
echo "all tests passed"
