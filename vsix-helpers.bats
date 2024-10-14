#!/usr/bin/env bats

load '/opt/homebrew/lib/bats-support/load.bash'
load '/opt/homebrew/lib/bats-assert/load.bash'

# Runs prior to every test
setup() {
    # Load our script file.
    source "${BATS_TEST_DIRNAME}/vsix-helpers.sh"
    export BATS_TEST_SKIPPED="" # workaround for bats bug
}

@test 'getExtensionInfo, publisher.package' {
    platform=$(vsixPlatform)
    output="$(getExtensionInfo publisher.package)"
    assert_equal "${output}" "publisher package latest"
}

@test 'getExtensionInfo, publisher.package-package' {
    platform=$(vsixPlatform)
    output="$(getExtensionInfo publisher.package-package)"
    assert_equal "${output}" "publisher package-package latest"
}

@test 'getExtensionInfo, publisher.package-0.0.1' {
    platform=$(vsixPlatform)
    output="$(getExtensionInfo publisher.package-0.0.1)"
    assert_equal "${output}" "publisher package 0.0.1"
}

@test 'getExtensionInfo, publisher.package-package-0.0.1' {
    platform=$(vsixPlatform)
    output="$(getExtensionInfo publisher.package-package-0.0.1)"
    assert_equal "${output}" "publisher package-package 0.0.1"
}

@test 'getExtensionInfo, publisher.package-package@0.0.1' {
    platform=$(vsixPlatform)
    output="$(getExtensionInfo publisher.package-package@0.0.1)"
    assert_equal "${output}" "publisher package-package 0.0.1"
}

@test 'getExtensionInfo, publisher.package-package-0.0.1@platform' {
    platform=$(vsixPlatform)
    output="$(getExtensionInfo publisher.package-package-0.0.1@platform)"
    assert_equal "${output}" "publisher package-package 0.0.1 platform"
}

@test 'getExtensionInfo, publisher' {
    refute [ getExtensionInfo publisher ]
}
