#!/bin/bash

set -e

source $(dirname $0)/helpers.sh

CERT=$(cd $(dirname $0) && pwd)/self_signed_cert_and_key.pem

setUp() {
  export TMPDIR=$(mktemp -d ${TMPDIR_ROOT}/hg-tests.XXXXXX)
}

assertTaggedCommitAtTip() {
  local dest=$1
  local expected_commit_id=$2
  local commit_id=$(hg log --cwd "$dest" --limit 1 --rev tip --template '{node}')
  local message=$(hg log --cwd "$dest" --rev "$commit_id" --template '{desc}')
  local parent_commit=$(hg log --cwd "$dest" --rev "${commit_id}^" --template '{node}')

  assertEquals "$expected_commit_id" "$parent_commit"

  local changed_files=$(hg log --cwd "$dest" --rev "$commit_id" --template '{files}')
  assertEquals ".hgtags" "$changed_files"
}

# TODO reformat and clean up tests

test_it_can_put_to_url() {
  local repo1=$(init_repo)

  local src=$(mktemp -d $TMPDIR/put-src.XXXXXX)
  local repo2=$src/repo
  hg clone $repo1 $repo2

  local tagged_commit=$(make_commit $repo2)
  # create a tag to push
  local ref=$(make_tag $repo2 some-tag)

  put_uri $repo1 $src repo | jq -e "
    .version == {ref: $(echo $ref | jq -R .)}
  "

  # update working directory in repo1
  hg checkout --cwd $repo1 default

  test -e $repo1/some-file
  test "$(get_working_dir_ref $repo1)" = $ref
  local actual_commit_id_of_tag=$(hg log --cwd "$repo1" --limit 1 --rev some-tag --template '{node}')
  assertEquals "$tagged_commit" "$actual_commit_id_of_tag"
}

test_it_can_put_to_url_with_no_branch() {
  local repo1=$(init_repo)

  local src=$(mktemp -d $TMPDIR/put-src.XXXXXX)
  local repo2=$src/repo
  hg clone $repo1 $repo2

  local tagged_commit=$(make_commit $repo2)
  # create a tag to push
  local ref=$(make_tag $repo2 some-tag)

  put_uri_no_branch $repo1 $src repo | jq -e "
    .version == {ref: $(echo $ref | jq -R .)}
  "

  # update working directory in repo1
  hg checkout --cwd $repo1 default

  test -e $repo1/some-file
  test "$(get_working_dir_ref $repo1)" = $ref
  local actual_commit_id_of_tag=$(hg log --cwd "$repo1" --limit 1 --rev some-tag --template '{node}')
  assertEquals "$tagged_commit" "$actual_commit_id_of_tag"
}

test_it_aborts_when_trying_to_tag_without_rebase_option() {
  local repo1=$(init_repo)

  local src=$(mktemp -d $TMPDIR/put-src.XXXXXX)
  local repo2=$src/repo
  hg clone $repo1 $repo2

  local ref=$(make_commit $repo2)

  echo some-tag-name > $src/some-tag-file

  ! put_uri_with_tag $repo1 $src some-tag-file repo || fail "expected tagging to fail without rebase option"
}

test_it_can_put_to_url_with_tag_from_a_non_tip_working_dir() {
  local repo1=$(init_repo)

  local src=$(mktemp -d $TMPDIR/put-src.XXXXXX)
  local repo2=$src/repo
  hg clone $repo1 $repo2

  local ref1=$(make_commit $repo2)
  local ref2=$(make_commit $repo2)
  local ref3=$(make_commit $repo2)
  hg checkout --cwd $repo2 $ref2

  echo some-tag-name > $src/some-tag-file

  put_uri_with_rebase_with_tag $repo1 $src some-tag-file repo | jq -e "
    .version == {ref: $(echo $ref2 | jq -R .)}
  "

  # switch back to master
  hg checkout --cwd $repo1 default

  test -e $repo1/some-file
  assertTaggedCommitAtTip "$repo1" "$ref2"

  local actual_commit_id_of_tag=$(hg log --cwd "$repo1" --limit 1 --rev 'some-tag-name' --template '{node}')
  assertEquals "$ref2" "$actual_commit_id_of_tag"
}

test_it_can_put_to_url_with_rebase() {
  local repo1=$(init_repo)

  local src=$(mktemp -d $TMPDIR/put-src.XXXXXX)
  local repo2=$src/repo
  hg clone $repo1 $repo2

  # make a commit that will require rebasing
  local baseref=$(make_commit_to_file $repo1 some-other-file)

  local ref=$(make_commit $repo2)

  local response=$(mktemp $TMPDIR/rebased-response.XXXXXX)

  local rebased_repo=$(mktemp -d "$TMPDIR/hg-repo-at-$ref.XXXXXX")
  TEST_REPO_AT_REF_DIR="$rebased_repo"
  export TEST_REPO_AT_REF_DIR
  put_uri_with_rebase "$repo1" "$src" "repo" "$rebased_repo" > $response
  unset TEST_REPO_AT_REF_DIR

  local rebased_ref=$(hg log --cwd "$rebased_repo" --rev tip --template '{node}')

  jq -e "
    .version == {ref: $(echo $rebased_ref | jq -R .)}
  " < $response

    jq -e "
    .metadata[0].value == $(echo $rebased_ref | jq -R .)
  " < $response

  # switch back to default
  hg checkout --cwd "$repo1" default

  test -e $repo1/some-file
  test "$(hg log --cwd $repo1 --rev tip --template '{node}')" = $rebased_ref

  local parent_of_tip=$(hg log --cwd "$repo1" --rev 'tip^' --template '{node}')
  assertEquals "$baseref" "$parent_of_tip"
}

test_it_can_put_to_url_with_rebase_with_tag() {
  local repo1=$(init_repo)

  local src=$(mktemp -d $TMPDIR/put-src.XXXXXX)
  local repo2=$src/repo
  hg clone $repo1 $repo2

  # make a commit that will require rebasing
  local baseref=$(make_commit_to_file $repo1 some-other-file)

  local ref=$(make_commit $repo2)

  echo some-tag-name > $src/some-tag-file

  local response=$(mktemp $TMPDIR/rebased-response.XXXXXX)

  local rebased_repo=$(mktemp -d "$TMPDIR/hg-repo-at-$ref.XXXXXX")
  TEST_REPO_AT_REF_DIR="$rebased_repo"
  export TEST_REPO_AT_REF_DIR
  put_uri_with_rebase_with_tag $repo1 $src some-tag-file repo > $response
  unset TEST_REPO_AT_REF_DIR

  local rebased_ref=$(hg log --cwd "$rebased_repo" --rev 'tip^' --template '{node}')

  jq -e "
    .version == {ref: $(echo $rebased_ref | jq -R .)}
  " < $response

  # switch back to master
  hg checkout --cwd "$repo1" default

  test -e $repo1/some-file

  assertTaggedCommitAtTip "$rebased_repo" "$rebased_ref"

  echo "assert tagged commit passed"
  local tag_value=$(hg log --cwd "$repo1" --rev some-tag-name --template '{node}')
  assertEquals "$rebased_ref" "$tag_value"
}

test_it_can_put_to_url_with_rebase_with_tag_and_prefix() {
  local repo1=$(init_repo)

  local src=$(mktemp -d $TMPDIR/put-src.XXXXXX)
  local repo2=$src/repo
  hg clone $repo1 $repo2

  # make a commit that will require rebasing
  local baseref=$(make_commit_to_file $repo1 some-other-file)

  local ref=$(make_commit $repo2)

  echo 1.0 > $src/some-tag-file

  local response=$(mktemp $TMPDIR/rebased-response.XXXXXX)

  local rebased_repo=$(mktemp -d "$TMPDIR/hg-repo-at-$ref.XXXXXX")
  TEST_REPO_AT_REF_DIR="$rebased_repo"
  export TEST_REPO_AT_REF_DIR
  put_uri_with_rebase_with_tag_and_prefix $repo1 $src some-tag-file v repo > $response
  unset TEST_REPO_AT_REF_DIR

  local rebased_ref=$(hg log --cwd "$rebased_repo" --rev tip^ --template '{node}')

  jq -e "
    .version == {ref: $(echo $rebased_ref | jq -R .)}
  " < $response

  # switch back to master
  hg checkout --cwd $repo1 default

  test -e $repo1/some-file

  assertTaggedCommitAtTip "$repo1" "$rebased_ref"

  test "$(hg log --cwd $repo1 --rev v1.0 --template '{node}')" = $rebased_ref
}

test_it_tries_to_rebase_repeatedly_in_race_conditions() {
  local repo1=$(init_repo)

  local src=$(mktemp -d $TMPDIR/put-src.XXXXXX)
  local repo2=$src/repo
  hg clone $repo1 $repo2

  # make a commit that will require rebasing
  local baseref1=$(make_commit_to_file $repo1 some-other-file)

  local ref=$(make_commit $repo2)

  local response=$(mktemp $TMPDIR/rebased-response.XXXXXX)

  background_commit_id_file=$(mktemp /tmp/hg-commit-id.XXXXXX)
  make_commit_after_1_second $repo1 > $background_commit_id_file &

  local rebased_repo=$(mktemp -d "$TMPDIR/hg-repo-at-$ref.XXXXXX")
  TEST_REPO_AT_REF_DIR="$rebased_repo"
  export TEST_REPO_AT_REF_DIR
  put_uri_with_rebase_and_race_conditions $repo1 $src repo > $response
  unset TEST_REPO_AT_REF_DIR

  local baseref2=$(cat $background_commit_id_file)
  local rebased_ref=$(hg log --cwd "$rebased_repo" --rev tip --template '{node}')

  jq -e "
    .version == {ref: $(echo $rebased_ref | jq -R .)}
  " < $response

  # switch back to default
  hg checkout --cwd "$repo1" default

  test -e $repo1/some-file
  test "$(hg log --cwd $repo1 --rev tip --template '{node}')" = $rebased_ref

  local parent_of_tip=$(hg log --cwd "$repo1" --rev 'tip^' --template '{node}')
  local grandparent_of_tip=$(hg log --cwd "$repo1" --rev 'tip^^' --template '{node}')

  assertEquals "$baseref2" "$parent_of_tip"
  assertEquals "$baseref1" "$grandparent_of_tip"
}

delete_repository_after_hg_pull() {
  local repo=$1
  # wait for hg pull to start
  while ! ps aux | grep -v grep | grep -q "hg pull"; do
    sleep 0.1
  done
  # wait for hg pull to end
  while ps aux | grep -v grep | grep -q "hg pull"; do
    sleep 0.1
  done
  rm -r $repo
}

test_it_aborts_on_unknown_push_errors() {
  local repo1=$(init_repo)

  local src=$(mktemp -d $TMPDIR/put-src.XXXXXX)
  local repo2=$src/repo
  hg clone $repo1 $repo2

  # make a commit that will require rebasing
  local baseref1=$(make_commit_to_file $repo1 some-other-file)

  local ref=$(make_commit $repo2)

  local response=$(mktemp $TMPDIR/rebased-response.XXXXXX)

  delete_repository_after_hg_pull $repo1 &

  local rebased_repo=$(mktemp -d "$TMPDIR/hg-repo-at-$ref.XXXXXX")
  TEST_REPO_AT_REF_DIR="$rebased_repo"
  export TEST_REPO_AT_REF_DIR
  ! put_uri_with_rebase_and_race_conditions $repo1 $src repo &> $response || fail "expected 'out' to have a non-zero exit code"
  unset TEST_REPO_AT_REF_DIR

  if ! grep "^failed with non-rebase error" $response; then
    fail "expected 'out' to abort after an unhandled push error"
  fi
}

test_it_checks_ssl_certificates() {
  local repo1=$(init_repo)

  local src=$(mktemp -d $TMPDIR/put-src.XXXXXX)
  local repo2=$src/repo
  hg clone $repo1 $repo2

  local tagged_commit=$(make_commit $repo2)
  # create a tag to push
  local ref=$(make_tag $repo2 some-tag)

  hg serve --cwd $repo1 --config 'web.allow_push=*' --address 127.0.0.1 --port 8000 --certificate $CERT &
  serve_pid=$!
  $(sleep 10; kill $serve_pid) &

  ! put_uri https://localhost:8000/ $src repo || fail "expected self-signed certificate to not be trusted"

  kill $serve_pid
  sleep 0.1
}

test_it_can_put_with_ssl_cert_checks_disabled() {
  local repo1=$(init_repo)

  local src=$(mktemp -d $TMPDIR/put-src.XXXXXX)
  local repo2=$src/repo
  hg clone $repo1 $repo2

  local tagged_commit=$(make_commit $repo2)
  # create a tag to push
  local ref=$(make_tag $repo2 some-tag)

  hg serve --cwd $repo1 --config 'web.allow_push=*' --address 127.0.0.1 --port 8000 --certificate $CERT &
  serve_pid=$!
  $(sleep 10; kill $serve_pid) &

  put_uri_insecure https://localhost:8000/ $src repo | jq -e "
    .version == {ref: $(echo $ref | jq -R .)}
  "

  # update working directory in repo1
  hg checkout --cwd $repo1 default

  test -e $repo1/some-file
  test "$(get_working_dir_ref $repo1)" = $ref
  local actual_commit_id_of_tag=$(hg log --cwd "$repo1" --limit 1 --rev some-tag --template '{node}')
  assertEquals "$tagged_commit" "$actual_commit_id_of_tag"

  kill $serve_pid
  sleep 0.1
}

source $(dirname $0)/shunit2
