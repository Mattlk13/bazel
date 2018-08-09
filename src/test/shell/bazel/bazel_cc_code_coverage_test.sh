#!/bin/bash -eu
#
# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Unit tests for tools/test/collect_cc_code_coverage.sh


# Load the test setup defined in the parent directory
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CURRENT_DIR}/../integration_test_setup.sh" \
  || { echo "integration_test_setup.sh not found!" >&2; exit 1; }


function setup_cc_sources() {
  mkdir -p sources
  cat << EOF > sources/a.h
int a(bool what);
EOF

  cat << EOF > sources/a.cc
#include "a.h"

int a(bool what) {
  if (what) {
    return 1;
  } else {
    return 2;
  }
}
EOF

  cat << EOF > sources/t.cc
#include <stdio.h>
#include "a.h"

int main(void) {
  a(true);
}
EOF
}

function setup_gcc_gcda_files() {

  cd sources/
  # Generate .gcno files.
  g++ -fprofile-arcs -ftest-coverage -c a.h a.cc t.cc
  # Produce instrumented binary.
  g++ -fprofile-arcs -ftest-coverage a.h a.cc t.cc -o test
  # Execute the test and generate test.gcda file.
  ./test

  mkdir -p $COVERAGE_DIR/sources/
  cp $PWD/a.gcda $COVERAGE_DIR/sources/a.gcda
  cp $PWD/t.gcda $COVERAGE_DIR/sources/t.gcda
  cd ..
}

function setup_script_environment() {
  export COVERAGE_DIR="$PWD/coverage_dir"
  mkdir -p $COVERAGE_DIR
  export ROOT="$PWD"
  export CC_COVERAGE_OUTPUT_FILE="$PWD/coverage_report.dat"
  export COVERAGE_MANIFEST="$PWD/coverage_manifest.txt"

  # The script expects gcov to be at $COVERAGE_DIR/gcov.
  gcov_location=$( which gcov )
  cp $gcov_location $COVERAGE_DIR/gcov

  # The script expects the output file to already exist.
  touch $CC_COVERAGE_OUTPUT_FILE
  echo "sources/a.gcno" >> $COVERAGE_MANIFEST
}

function check_env() {
  if [[ ! -x /usr/bin/lcov ]]; then
    fail "lcov not installed. Skipping test."
  fi

  if [[ -z $( which gcov ) ]]; then
    fail "gcov not installed."
  fi

  if [[ -z $( which g++ ) ]]; then
    fail "g++ not installed."
  fi
}

function test_cc_test_coverage() {
  check_env

  setup_script_environment
  setup_cc_sources
  setup_gcc_gcda_files

  eval tools/test/collect_cc_coverage.sh

  cat <<EOF > result.dat
TN:
SF:a.cc
FN:3,_Z1ab
FNDA:1,_Z1ab
FNF:1
FNH:1
DA:3,1
DA:4,1
DA:5,1
DA:7,0
LF:4
LH:3
end_of_record
TN:
EOF

  cat $CC_COVERAGE_OUTPUT_FILE
  diff result.dat "$CC_COVERAGE_OUTPUT_FILE" >> $TEST_log
  cmp result.dat "$CC_COVERAGE_OUTPUT_FILE" || fail "Coverage output file is different than the expected file"
}

function test_cc_test_coverage_gcov() {
  check_env

  setup_script_environment
  setup_cc_sources
  setup_gcc_gcda_files
  export GCOV_COVERAGE=1
  export CC_COVERAGE_OUTPUT_FILE="$COVERAGE_DIR/_coverage.gcov"

  eval tools/test/collect_cc_coverage.sh

  cat <<EOF > result.dat
file:a.cc
function:3,1,_Z1ab
lcount:3,1
lcount:4,1
branch:4,taken
branch:4,nottaken
lcount:5,1
lcount:7,0
EOF

  diff result.dat "$CC_COVERAGE_OUTPUT_FILE" >> $TEST_log || fail "Diff failed"
  cmp result.dat "$CC_COVERAGE_OUTPUT_FILE" || fail "Coverage output file is different than the expected file"
}

run_suite "testing tools/test/collect_cc_coverage.sh"