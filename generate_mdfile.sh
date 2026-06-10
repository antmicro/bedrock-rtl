#!/bin/bash

cat ./.bazel-test-verilator.log | grep 'FAILED in\|PASSED in' > .bazel-testresults-only.log

echo "|Test name|Test result|Test duration|"
echo "|--------:|----------:|------------:|"

while read p; do
  test_name=$(echo "$p" | tr -s ' ' | cut -d" " -f1)
  test_result=$(echo "$p" | tr -s ' ' | cut -d" " -f2)
  test_prefix=""
  if [ $test_result == "PASSED" ]; then
    test_prefix='<span style="color:green">'
  elif [ $test_result == "FAILED" ]; then
    test_prefix='<span style="color:red">'
  fi
  test_result="$test_prefix $test_result </span>"
  test_time=$(echo "$p" | tr -s ' ' | cut -d" " -f4)
  echo "|$test_name|$test_result|$test_time|"
done < .bazel-testresults-only.log
