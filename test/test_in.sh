#!/bin/sh

set -e

source $(dirname $0)/helpers.sh

setUp() {
  export TMPDIR=$(mktemp -d ${TMPDIR_ROOT}/hg-tests.XXXXXX)
}

test_it_can_get_from_url() {
  local repo=$(init_repo)
  local ref=$(make_commit $repo)
  local dest=$TMPDIR/destination

  local expected=$(echo "{\"ref\": $(echo $ref | jq -R .)}" | jq ".")
  assertEquals "$expected" "$(get_uri $repo $dest | jq '.version')"

  if [ ! -e "$dest/some-file" ]; then
    fail "expected some-file to exist in the working directory"
  fi
  assertEquals "$ref" "$(get_working_dir_ref $dest)"
}

test_it_can_get_from_url_at_ref() {
  local repo=$(init_repo)
  local ref1=$(make_commit $repo)
  local ref2=$(make_commit $repo)

  local dest=$TMPDIR/destination

  local expected1=$(echo "{\"ref\": $(echo $ref1 | jq -R .)}" | jq ".")
  assertEquals "$expected1" "$(get_uri_at_ref $repo $ref1 $dest | jq '.version')"

  if [ ! -e "$dest/some-file" ]; then
    fail "expected some-file to exist in the working directory"
  fi
  assertEquals "$ref1" "$(get_working_dir_ref $dest)"

  rm -rf $dest

  local expected2=$(echo "{\"ref\": $(echo $ref2 | jq -R .)}" | jq ".")
  assertEquals "$expected2" "$(get_uri_at_ref $repo $ref2 $dest | jq '.version')"

  if [ ! -e "$dest/some-file" ]; then
    fail "expected some-file to exist in the working directory"
  fi
  assertEquals "$ref2" "$(get_working_dir_ref $dest)"
}

test_it_can_get_from_url_at_branch() {
  local repo=$(init_repo)
  local ref1=$(make_commit_to_branch $repo 'branch_a')
  local ref2=$(make_commit_to_branch $repo 'branch_b')

  local dest=$TMPDIR/destination

  local expected1=$(echo "{\"ref\": $(echo $ref1 | jq -R .)}" | jq ".")
  assertEquals "$expected1" "$(get_uri_at_branch $repo 'branch_a' $dest | jq '.version')"

  if [ ! -e "$dest/some-file" ]; then
    fail "expected some-file to exist in the working directory"
  fi
  assertEquals "$ref1" "$(get_working_dir_ref $dest)"

  rm -rf $dest

  local expected2=$(echo "{\"ref\": $(echo $ref2 | jq -R .)}" | jq ".")
  assertEquals "$expected2" "$(get_uri_at_branch $repo branch_b $dest | jq '.version')"

    if [ ! -e "$dest/some-file" ]; then
    fail "expected some-file to exist in the working directory"
  fi
  assertEquals "$ref2" "$(get_working_dir_ref $dest)"
}

test_it_can_get_from_url_only_single_branch() {
  local repo=$(init_repo)
  local ref=$(make_commit $repo)
  local dest=$TMPDIR/destination

  local expected=$(echo "{\"ref\": $(echo $ref | jq -R .)}" | jq ".")
  assertEquals "$expected" "$(get_uri $repo $dest | jq '.version')"

  ! check_branch_exists "$dest" bogus || fail "branch was fetched, expected it to not exist locally"
}

test_it_returns_metadata() {
  local repo=$(init_repo)
  local ref=$(make_commit_to_file_on_branch_as_user_at_date $repo "some-file" "default" "expected username <expected@example.com>" "2016-12-31 12:34:56 UTC" "test message")
  local dest=$TMPDIR/destination

  local expected=$(echo "[
      {\"name\": \"commit\", \"value\": $(echo $ref | jq -R .)},
      {\"name\": \"author\", \"value\": \"expected username <expected@example.com>\"},
      {\"name\": \"author_date\", \"value\": \"2016-12-31 12:34:56 +0000\", \"type\": \"time\"},
      {\"name\": \"message\", \"value\": \"test message\", \"type\": \"message\"}
    ]" | jq ".")
 
  assertEquals "$expected" "$(get_uri $repo $dest | jq '.metadata')"  
}

test_it_updates_subrepositories() {
  local dest=$TMPDIR/destination
  local repo=$(init_repo)
  local subrepo=$(init_repo)
  local subrepo_ref=$(make_commit $subrepo)

  echo "subrepo = $subrepo" > $repo/.hgsub
  # clone subrepo into $repo
  hg clone --cwd $repo $subrepo "subrepo" # &>/dev/null
  # hg add .hgsub in $repo
  hg add --cwd $repo .hgsub
  # make a commit in $repo to add both the .hgsub file and the subrepo state
  hg commit --cwd $repo -m "test repo commit"

  # clone $repo, make sure subrepo is updated to the latest commit id
  get_uri $repo $dest &>/dev/null
  assertEquals "$subrepo_ref subrepo" "$(cat $dest/.hgsubstate)"

  if [ ! -e "$dest/subrepo/some-file" ]; then
    fail "expected some-file to exist in the cloned subrepository"
  fi
}

source $(dirname $0)/shunit2
