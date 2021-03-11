#!/bin/bash

set -e

source $(dirname $0)/helpers.sh

CERT=$(cd $(dirname $0) && pwd)/self_signed_cert_and_key.pem

setUp() {
  export TMPDIR=$(mktemp -d ${TMPDIR_ROOT}/hg-tests.XXXXXX)
}

test_it_can_check_from_head() {
  local repo=$(init_repo)
  local ref=$(make_commit $repo)

  local expected=$(echo "[{\"ref\": $(echo $ref | jq -R .)}]"|jq ".")

  assertEquals "$expected" "$(check_uri $repo | jq '.')"
}

test_it_can_check_from_a_ref() {
  local repo=$(init_repo)
  local ref1=$(make_commit $repo)
  local ref2=$(make_commit $repo)
  local ref3=$(make_commit $repo)

  local expected=$(echo "[{\"ref\": $(echo $ref2 | jq -R .)}, {\"ref\": $(echo $ref3 | jq -R .)}]"|jq ".")
  assertEquals "$expected" "$(check_uri_from $repo $ref1 | jq '.')"
}

test_it_can_check_from_a_bogus_sha() {
  local repo=$(init_repo)
  local ref1=$(make_commit $repo)
  local ref2=$(make_commit $repo)

  local expected=$(echo "[{\"ref\": $(echo $ref2 | jq -R .)}]"|jq ".") 
  assertEquals "$expected" "$(check_uri_from $repo bogus-ref | jq '.')"
}

test_it_skips_ignored_paths() {
  local repo=$(init_repo)
  local ref1=$(make_commit_to_file $repo file-a)
  local ref2=$(make_commit_to_file $repo file-b)
  local ref3=$(make_commit_to_file $repo file-c)

  hg log --stat --cwd $repo
  local expected1=$(echo "[
  		{\"ref\": $(echo $ref2 | jq -R .)}
  	]" | jq ".")
  assertEquals "$expected1" "$(check_uri_ignoring $repo file-c | jq '.')"

  local expected2=$(echo "[
  		{\"ref\": $(echo $ref2 | jq -R .)}
  	]" | jq ".")
  assertEquals "$expected2" "$(check_uri_from_ignoring $repo $ref1 file-c | jq '.')"

  local ref4=$(make_commit_to_file $repo file-b)

  local expected3=$(echo "[
  		{\"ref\": $(echo $ref4 | jq -R .)}
		]" | jq ".")
  assertEquals "$expected3" "$(check_uri_ignoring $repo file-c | jq '.')"

  local expected4=$(echo "[
      {\"ref\": $(echo $ref2 | jq -R .)},
      {\"ref\": $(echo $ref4 | jq -R .)}
    ]" | jq ".")
  assertEquals "$expected4" "$(check_uri_from_ignoring $repo $ref1 file-c | jq '.')"

  local ref5=$(make_commit_to_file $repo file-d)

  local expected5=$(echo "[
    {\"ref\": $(echo $ref5 | jq -R .)}
  ]" | jq ".")
  assertEquals "$expected5" "$(check_uri_from_ignoring $repo $ref1 file-c file-b | jq '.')"
}

test_it_checks_correct_branch() {
  local repo=$(init_repo)
  local ref1=$(make_commit $repo)
  local ref2=$(make_commit_to_branch $repo some-branch )

  # Test initial clone and that check doesn't see descendants that aren't in the given branch
  local expected1=$(echo "[{\"ref\": $(echo $ref1 | jq -R .)}]"|jq ".")
  assertEquals "$expected1" "$(check_uri $repo | jq '.')"

  # Test check's first pull is still returning the same result, as above
  local expected2=$(echo "[{\"ref\": $(echo $ref1 | jq -R .)}]"|jq ".")
  assertEquals "$expected2" "$(check_uri $repo | jq '.')"

  # Test check doesn't see changes to in other descendant branches when checking from a revision
  local ref3=$(make_commit_to_branch $repo some-branch )

  local expected3="[]"
  assertEquals "$expected3" "$(check_uri_from $repo $ref1 | jq '.')"

  # Test check only sees changes to its branch when checking from a revision
  local ref4=$(make_commit $repo)

  local expected4=$(echo "[{\"ref\": $(echo $ref4 | jq -R .)}]"|jq ".")
  assertEquals "$expected4" "$(check_uri_from $repo $ref1 | jq '.')"

  # Test check doesn't see changes to in parent branches
  local expected5=$(echo "[{\"ref\": $(echo $ref3 | jq -R .)}]"|jq ".")
  assertEquals "$expected5" "$(check_uri_with_branch $repo some-branch | jq '.')"

  # Test check doesn't see changes to in parent branches when checking from a revision
  local expected6=$(echo "[{\"ref\": $(echo $ref3 | jq -R .)}]"|jq ".")
  assertEquals "$expected6" "$(check_uri_with_branch_from $repo $ref2 some-branch | jq '.')"
}

test_check_checks_out_expected_branch_after_clone_and_pull() {
  local repo=$(init_repo)
  local ref1=$(make_commit_to_branch $repo some-branch )
  local ref2=$(make_commit $repo)

  # first check triggers clone
  local expected1=$(echo "[{\"ref\": $(echo $ref1 | jq -R .)}]"|jq ".")
  assertEquals "$expected1" "$(check_uri_with_branch $repo some-branch | jq '.')"
  assertEquals "some-branch" $(hg branch --cwd $TMPDIR/hg-resource-repo-cache)

  # second check triggers pull
  local expected2=$(echo "[{\"ref\": $(echo $ref1 | jq -R .)}]"|jq ".")
  assertEquals "$expected2" "$(check_uri_with_branch $repo some-branch | jq '.')"
  assertEquals "some-branch" $(hg branch --cwd $TMPDIR/hg-resource-repo-cache)
}

test_it_checks_given_paths() {
  local repo=$(init_repo)
  local ref1=$(make_commit_to_file $repo file-a)
  local ref2=$(make_commit_to_file $repo file-b)
  local ref3=$(make_commit_to_file $repo file-c)

  local expected1=$(echo "[{\"ref\": $(echo $ref3 | jq -R .)}]" | jq ".")
  assertEquals "$expected1" "$(check_uri_paths $repo file-c | jq '.')"

  local expected2=$(echo "[{\"ref\": $(echo $ref3 | jq -R .)}]" | jq ".")
  assertEquals "$expected2" "$(check_uri_from_paths $repo $ref1 file-c | jq '.')"

  local ref4=$(make_commit_to_file $repo file-b)

  local expected3=$(echo "[{\"ref\": $(echo $ref3 | jq -R .)}]" | jq ".")
  assertEquals "$expected3" "$(check_uri_paths $repo file-c | jq '.')"

  local ref5=$(make_commit_to_file $repo file-c)

  local expected4=$(echo "[
      {\"ref\": $(echo $ref3 | jq -R .)},
      {\"ref\": $(echo $ref5 | jq -R .)}
    ]" | jq ".")
  assertEquals "$expected4" "$(check_uri_from_paths $repo $ref1 file-c | jq '.')"
}

test_it_checks_given_ignored_paths() {
  local repo=$(init_repo)
  local ref1=$(make_commit_to_file $repo file-a)
  local ref2=$(make_commit_to_file $repo file-b)
  local ref3=$(make_commit_to_file $repo some-file)

  local expected1=$(echo "[{\"ref\": $(echo $ref1 | jq -R .)}]" | jq ".")
  assertEquals "$expected1" "$(check_uri_paths_ignoring $repo 'file-.*' file-b | jq '.')"

  local expected2=$(echo "[]" | jq ".")
  assertEquals "$expected2" "$(check_uri_from_paths_ignoring $repo $ref1 'file-.*' 'file-b' | jq '.')"

  local ref4=$(make_commit_to_file $repo file-b)

  local expected3=$(echo "[{\"ref\": $(echo $ref1 | jq -R .)}]" | jq ".")
  assertEquals "$expected3" "$(check_uri_paths_ignoring $repo 'file-.*' 'file-b' | jq '.')"

  local ref5=$(make_commit_to_file $repo file-a)

  local expected4=$(echo "[{\"ref\": $(echo $ref5 | jq -R .)}]" | jq ".")
  assertEquals "$expected4" "$(check_uri_paths_ignoring $repo 'file-.*' 'file-b' | jq '.')"

  local ref6=$(make_commit_to_file $repo file-c)

  local ref7=$(make_commit_to_file $repo some-file)

  local expected5=$(echo "[
      {\"ref\": $(echo $ref5 | jq -R .)},
      {\"ref\": $(echo $ref6 | jq -R .)}
    ]" | jq ".")
  assertEquals "$expected5" "$(check_uri_from_paths_ignoring $repo $ref1 'file-.*' 'file-b' | jq '.')"

  local expected6=$(echo "[
     {\"ref\": $(echo $ref5 | jq -R .)}
   ]" | jq ".")
  assertEquals "$expected6" "$(check_uri_from_paths_ignoring $repo $ref1 'file-.*' 'file-b' 'file-c' | jq '.')"
}

test_it_skips_marked_commits() {
  local repo=$(init_repo)
  local ref1=$(make_commit $repo)
  local ref2=$(make_commit_to_be_skipped $repo)
  local ref3=$(make_commit $repo)
   
  local expected=$(echo "[{\"ref\": $(echo $ref3 | jq -R .)}]" | jq ".")
  
  assertEquals "$expected" "$(check_uri_from $repo $ref1 | jq '.')"
}

test_it_skips_marked_commits_with_no_version() {
  local repo=$(init_repo)
  local ref1=$(make_commit $repo)
  local ref2=$(make_commit_to_be_skipped $repo)
  local ref3=$(make_commit_to_be_skipped $repo)

  local expected=$(echo "[
     {\"ref\": $(echo $ref1 | jq -R .)}
   ]" | jq ".")

  assertEquals "$expected" "$(check_uri $repo | jq '.')"
}

test_it_fails_if_key_has_password() {
  local repo=$(init_repo)
  local ref=$(make_commit $repo)

  local key=$TMPDIR/key-with-passphrase
  ssh-keygen -f $key -N some-passphrase

  local failed_output=$TMPDIR/failed-output
  if check_uri_with_key $repo $key 2>$failed_output; then
    fail "checking should have failed"
  fi

  assertEquals "Private keys with passphrases are not supported." "$(cat $failed_output)"
}

test_it_can_check_with_tag_filter() {
  local repo=$(init_repo)
  local ref1=$(make_commit $repo)
  local ref2=$(make_annotated_tag $repo "1.0-staging" "a tag")
  local ref3=$(make_commit $repo)
  local ref4=$(make_annotated_tag $repo "1.0-production" "another tag")
  local ref5=$(make_commit $repo)

  local expected=$(echo "[{\"ref\": $(echo $ref1 | jq -R .)}]" | jq ".")
  assertEquals "$expected" "$(check_uri_with_tag_filter $repo '-staging$' | jq '.')"
}

test_it_can_check_with_tag_filter_from_a_ref() {
  local repo=$(init_repo)
  local ref1=$(make_commit $repo)
  local ref2=$(make_annotated_tag $repo "1.0-staging" "a tag")
  local ref3=$(make_commit $repo)
  local ref4=$(make_annotated_tag $repo "1.0-production" "another tag")
  local ref5=$(make_commit $repo)
  local ref6=$(make_annotated_tag $repo "1.1-staging" "much tag")

  local expected=$(echo "[{\"ref\": $(echo $ref5 | jq -R .)}]" | jq ".")
  assertEquals "$expected" "$(check_uri_with_tag_filter_from_ref $repo $ref2 '-staging$' | jq '.')"
}

test_it_can_check_with_revset_filter() {
  local repo=$(init_repo)
  local ref1=$(make_commit $repo)
  local ref2=$(make_annotated_tag $repo "1.0-staging" "a tag")
  local ref3=$(make_commit $repo)
  local ref4=$(make_annotated_tag $repo "1.0-production" "another tag")
  local ref5=$(make_commit $repo)

  local expected=$(echo "[{\"ref\": $(echo $ref1 | jq -R .)}]" | jq ".")
  assertEquals "$expected" "$(check_uri_with_revset_filter $repo 'tag("re:-staging$")' | jq '.')"
}

test_it_can_check_with_revset_filter_from_a_ref() {
  local repo=$(init_repo)
  local ref1=$(make_commit $repo)
  local ref2=$(make_annotated_tag $repo "1.0-staging" "a tag")
  local ref3=$(make_commit $repo)
  local ref4=$(make_annotated_tag $repo "1.0-production" "another tag")
  local ref5=$(make_commit $repo)
  local ref6=$(make_annotated_tag $repo "1.1-staging" "much tag")

  local expected=$(echo "[{\"ref\": $(echo $ref5 | jq -R .)}]" | jq ".")
  assertEquals "$expected" "$(check_uri_with_revset_filter_from_ref $repo $ref2 'tag("re:-staging$")' | jq '.')"
}

test_it_can_check_from_head_only_fetching_single_branch() {
  local repo=$(init_repo)
  local ref=$(make_commit $repo)
  local cachedir="$TMPDIR/hg-resource-repo-cache"
  
  local expected=$(echo "[{\"ref\": $(echo $ref | jq -R .)}]" | jq ".")
  assertEquals "$expected" "$(check_uri $repo | jq '.')"
  
  ! check_branch_exists "$cachedir" bogus || fail "branch was fetched, expected it to not exist locally"
}

test_user_cannot_inject_query_through_include_param() {
  local repo=$(init_repo)
  local ref1=$(make_commit_to_file $repo "'file-a'")
  local ref2=$(make_commit_to_file $repo "'file-b'")
  local ref3=$(make_commit_to_file $repo "file-c'")

  local expected1=$(echo "[{\"ref\": $(echo $ref2 | jq -R .)}]" | jq ".")
  assertEquals "$expected1" "$(check_uri_paths $repo "'file-b'" | jq '.')"

  local expected2=$(echo "[{\"ref\": $(echo $ref3 | jq -R .)}]" | jq ".")
  assertEquals "$expected2" "$(check_uri_from_paths $repo $ref1 "file-c'" | jq '.')"

  local ref4=$(make_commit_to_file $repo "'file-b'")

  local expected3=$(echo "[{\"ref\": $(echo $ref3 | jq -R .)}]" | jq ".")
  assertEquals "$expected3" "$(check_uri_paths $repo "file-c'" | jq '.')"

  local ref5=$(make_commit_to_file $repo "file-c'")

  local expected4=$(echo "[
      {\"ref\": $(echo $ref3 | jq -R .)},
      {\"ref\": $(echo $ref5 | jq -R .)}
    ]" | jq ".")
  assertEquals "$expected4" "$(check_uri_from_paths $repo $ref1 "file-c'" | jq '.')"
}

test_user_cannot_inject_query_through_exclude_param() {
  local repo=$(init_repo)
  local filea="'file-a'"
  local fileb="'file-b'"
  local filec="'file-c'"
  local file_wilcard="'file-.*"
  local ref1=$(make_commit_to_file $repo "$filea")
  local ref2=$(make_commit_to_file $repo "$fileb")
  local ref3=$(make_commit_to_file $repo "'some-file'")

  local expected1=$(echo "[{\"ref\": $(echo $ref1 | jq -R .)}]" | jq ".")
  assertEquals "$expected1" "$(check_uri_paths_ignoring $repo $file_wilcard $fileb | jq '.')"

  local expected2=$(echo "[]" | jq ".")
  assertEquals "$expected2" "$(check_uri_from_paths_ignoring $repo $ref1 $file_wilcard $fileb | jq '.')"

  local ref4=$(make_commit_to_file $repo $fileb)

  local expected3=$(echo "[{\"ref\": $(echo $ref1 | jq -R .)}]" | jq ".")
  assertEquals "$expected3" "$(check_uri_paths_ignoring $repo $file_wilcard $fileb | jq '.')"

  local ref5=$(make_commit_to_file $repo $filea)

  local expected4=$(echo "[{\"ref\": $(echo $ref5 | jq -R .)}]" | jq ".")
  assertEquals "$expected4" "$(check_uri_paths_ignoring $repo $file_wilcard $fileb | jq '.')"

  local ref6=$(make_commit_to_file $repo $filec)

  local ref7=$(make_commit_to_file $repo some-file)

  local expected5=$(echo "[
      {\"ref\": $(echo $ref5 | jq -R .)},
      {\"ref\": $(echo $ref6 | jq -R .)}
    ]" | jq ".")
  assertEquals "$expected5" "$(check_uri_from_paths_ignoring $repo $ref1 $file_wilcard $fileb | jq '.')"

  local expected6=$(echo "[
     {\"ref\": $(echo $ref5 | jq -R .)}
   ]" | jq ".")
  assertEquals "$expected6" "$(check_uri_from_paths_ignoring $repo $ref1 $file_wilcard $fileb $filec | jq '.')"
}

 test_user_cannot_inject_query_with_tag_filter() {
  local repo=$(init_repo)
  local ref1=$(make_commit $repo)
  local ref2=$(make_annotated_tag $repo "1.0-staging'" "a tag")
  local ref3=$(make_commit $repo)
  local ref4=$(make_annotated_tag $repo "1.0-production'" "another tag")
  local ref5=$(make_commit $repo)
  local ref6=$(make_annotated_tag $repo "1.1-staging'" "much tag")

  local expected=$(echo "[{\"ref\": $(echo $ref5 | jq -R .)}]" | jq ".")
  local filenameWithApostrophe="-staging'$"
  assertEquals "$expected" "$(check_uri_with_tag_filter_from_ref $repo $ref2 $filenameWithApostrophe | jq '.')"
}

test_backslash_is_escaped_in_include_param() {
  local filenameA="'file-a\\'"
  local filenameB="'file-b\\'"
  local filenameC="file-c'"
  local repo=$(init_repo)
  local ref1=$(make_commit_to_file $repo $filenameA)
  local ref2=$(make_commit_to_file $repo $filenameB)
  local ref3=$(make_commit_to_file $repo $filenameC)

  local expected1=$(echo "[{\"ref\": $(echo $ref2 | jq -R .)}]" | jq ".")
  assertEquals "$expected1" "$(check_uri_paths $repo $filenameB | jq '.')"

  local expected2=$(echo "[{\"ref\": $(echo $ref3 | jq -R .)}]" | jq ".")
  assertEquals "$expected2" "$(check_uri_from_paths $repo $ref1 $filenameC | jq '.')"

  local ref4=$(make_commit_to_file $repo $filenameB)

  local expected3=$(echo "[{\"ref\": $(echo $ref3 | jq -R .)}]" | jq ".")
  assertEquals "$expected3" "$(check_uri_paths $repo $filenameC | jq '.')"

  local ref5=$(make_commit_to_file $repo $filenameC)

  local expected4=$(echo "[
      {\"ref\": $(echo $ref3 | jq -R .)},
      {\"ref\": $(echo $ref5 | jq -R .)}
    ]" | jq ".")
  assertEquals "$expected4" "$(check_uri_from_paths $repo $ref1 $filenameC | jq '.')"
}

 test_backslash_is_escaped_in_tag_filter_param() {
  local repo=$(init_repo)
  local ref1=$(make_commit $repo)
  local ref2=$(make_annotated_tag $repo "1.0-staging\\'" "a tag")
  local ref3=$(make_commit $repo)
  local ref4=$(make_annotated_tag $repo "1.0-production\\'" "another tag")
  local ref5=$(make_commit $repo)
  local ref6=$(make_annotated_tag $repo "1.1-staging\\'" "much tag")

  local expected=$(echo "[{\"ref\": $(echo $ref5 | jq -R .)}]" | jq ".")
  local filenameWithBackslashApostrophe="-staging\\'$"
  assertEquals "$expected" "$(check_uri_with_tag_filter_from_ref $repo $ref2 $filenameWithBackslashApostrophe | jq '.')"
}

test_it_checks_ssl_certificates() {
  local repo=$(init_repo)
  local ref1=$(make_commit $repo)

  hg serve --cwd $repo --address 127.0.0.1 --port 8000 --certificate $CERT &
  serve_pid=$!
  $(sleep 10; kill $serve_pid) &

  ! check_uri https://127.0.0.1:8000/ || fail "expected self-signed certificate to not be trusted"
  kill $serve_pid
  sleep 0.1
}

test_it_can_disable_ssl_certificate_verification() {
  local repo=$(init_repo)
  local ref1=$(make_commit $repo)

  hg serve --cwd $repo --address 127.0.0.1 --port 8000 --certificate $CERT &
  serve_pid=$!
  $(sleep 10; kill $serve_pid) &

  local expected=$(echo "[{\"ref\": $(echo $ref1 | jq -R .)}]"|jq ".")
  assertEquals "$expected" "$(check_uri_insecure https://127.0.0.1:8000/ | jq '.')"

  kill $serve_pid
  sleep 0.1
}

source $(dirname $0)/shunit2
