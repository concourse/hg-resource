#!/bin/bash

set -e -u

set -o pipefail

resource_dir=/opt/resource

run() {
  export TMPDIR=$(mktemp -d ${TMPDIR_ROOT}/hg-tests.XXXXXX)

  echo -e 'running \e[33m'"$@"$'\e[0m...'
  eval "$@" 2>&1 | sed -e 's/^/  /g'
  echo ""
}

write_random_bytes() {
  dd if=/dev/urandom bs=256 count=1 2>/dev/null
}

init_repo() {
  (
    set -e

    cd $(mktemp -d $TMPDIR/repo.XXXXXX)

    hg init -q

    write_random_bytes > a_file

    hg add a_file

    # start with an initial commit
    hg commit \
      --config ui.username='test <test@example.com>' \
      -q -m "init"

    # create some bogus branch
    hg branch -q bogus 

    write_random_bytes > another_file

    hg add another_file

    # start with an initial commit
    hg commit \
      --config ui.username='test <test@example.com>' \
      -q -m "commit on other branch"

    # back to default
    hg checkout -q default

    # print resulting repo
    pwd
  )
}

init_repo_with_submodule() {
  local submodule=$(init_repo)
  make_commit $submodule >/dev/null
  make_commit $submodule >/dev/null

  local project=$(init_repo)
  git -C $project submodule add "file://$submodule" >/dev/null
  git -C $project commit -m "Adding Submodule" >/dev/null
  echo $project,$submodule
}

get_working_dir_ref() {
  local dest=$1
  local commit_id=$(hg identify --cwd "$dest" --id)
  hg log --cwd "$dest" --limit 1 --rev "$commit_id" --template '{node}'
}

make_commit_to_file_on_branch() {
  local repo=$1
  local file=$2
  local branch=$3
  local msg=${4-}

  hg branch -q --cwd $repo $branch

  # ensure branch exists
  if ! check_branch_exists $repo $branch; then
    # make sure we branch from default
    hg checkout -q --cwd $repo default
    hg branch -q --cwd $repo $branch
  else
    hg checkout -q --cwd $repo $branch
  fi

  # modify file and commit
  echo x >> $repo/$file
  hg add --cwd $repo $file 2>/dev/null
  hg commit --cwd $repo \
    --config ui.username='test <test@example.com>' \
    -q -m "commit $(wc -l $repo/$file) $msg"

  # output resulting sha
  hg log --cwd $repo --limit 1 --template "{node}"
}

make_commit_to_file_on_branch_as_user_at_date() {
  local repo=$1
  local file=$2
  local branch=$3
  local user=$4
  local date=$5
  local msg=${6-}

  hg branch --cwd $repo $branch &>/dev/null

  # modify file and commit
  echo x >> $repo/$file
  hg add --cwd $repo $file 2>/dev/null
  hg commit --cwd $repo \
    --user "$user" \
    --date "$date" \
    -q -m "$msg"

  # output resulting sha
  hg log --cwd $repo --limit 1 --template "{node}"
}

make_commit_to_file() {
  make_commit_to_file_on_branch $1 $2 default "${3-}"
}

make_commit_to_branch() {
  make_commit_to_file_on_branch $1 some-file $2
}

make_commit() {
  make_commit_to_file $1 some-file
}

make_commit_after_1_second() {
  local repo=$1
  sleep 1
  local commit_id=$(make_commit_to_file "$repo" third-file)
  echo $commit_id
  echo "made a commit in the background: $commit_id" >&2
}

make_commit_to_be_skipped() {
  make_commit_to_file $1 some-file "[ci skip]"
}

make_empty_commit() {
  local repo=$1
  local msg=${2-}

  git -C $repo \
    -c user.name='test' \
    -c user.email='test@example.com' \
    commit -q --allow-empty -m "commit $msg"

  # output resulting sha
  git -C $repo rev-parse HEAD
}

make_annotated_tag() {
  local repo=$1
  local tag=$2
  local msg=$3

  hg tag --cwd $repo --message "$msg" "$tag"
  # tag commits are always added as tip
  hg log --cwd $repo --rev tip --template '{node}\n'
}

make_tag() {
  local repo=$1
  local tag=$2
  hg tag --cwd $repo "$tag"
  # tag commits are always added as tip
  hg log --cwd $repo --rev tip --template '{node}\n'
}

check_branch_exists() {
  local repo=$1
  local branch=$2
  hg log --cwd "$repo" --limit 1 --branch "$branch" &>/dev/null
}

check_uri() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .)
    }
  }" | ${resource_dir}/check | tee /dev/stderr
}

check_uri_insecure() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .),
      skip_ssl_verification: true
    }
  }" | ${resource_dir}/check | tee /dev/stderr
}

check_uri_with_branch() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .),
      branch: $(echo $2 | jq -R .)
    }
  }" | ${resource_dir}/check | tee /dev/stderr
}

check_uri_with_key() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .),
      private_key: $(cat $2 | jq -s -R .)
    }
  }" | ${resource_dir}/check | tee /dev/stderr
}


check_uri_ignoring() {
  local uri=$1

  shift

  jq -n "{
    source: {
      uri: $(echo $uri | jq -R .),
      ignore_paths: $(echo "$@" | jq -R '. | split(" ")')
    }
  }" | ${resource_dir}/check | tee /dev/stderr
}

check_uri_paths() {
  local uri=$1

  shift

  jq -n "{
    source: {
      uri: $(echo $uri | jq -R .),
      paths: $(echo "$@" | jq -R '. | split(" ")')
    }
  }" | ${resource_dir}/check | tee /dev/stderr
}

check_uri_paths_ignoring() {
  local uri=$1
  local paths=$2

  shift 2

  jq -n "{
    source: {
      uri: $(echo $uri | jq -R .),
      paths: [$(echo "$paths" | jq -R .)],
      ignore_paths: $(echo "$@" | jq -R '. | split(" ")')
    }
  }" | ${resource_dir}/check | tee /dev/stderr
}

check_uri_from() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .)
    },
    version: {
      ref: $(echo $2 | jq -R .)
    }
  }" | ${resource_dir}/check | tee /dev/stderr
}

check_uri_with_branch_from() {
  local uri=$1
  local ref=$2
  local branch=$3

  shift 3

  jq -n "{
    source: {
      uri: $(echo $uri | jq -R .),
      branch: $(echo $branch | jq -R .)
    },
    version: {
      ref: $(echo $ref | jq -R .)
    }
  }" | ${resource_dir}/check | tee /dev/stderr
}

check_uri_from_ignoring() {
  local uri=$1
  local ref=$2

  shift 2

  jq -n "{
    source: {
      uri: $(echo $uri | jq -R .),
      ignore_paths: $(echo "$@" | jq -R '. | split(" ")')
    },
    version: {
      ref: $(echo $ref | jq -R .)
    }
  }" | ${resource_dir}/check | tee /dev/stderr
}

check_uri_from_paths() {
  local uri=$1
  local ref=$2

  shift 2

  jq -n "{
    source: {
      uri: $(echo $uri | jq -R .),
      paths: $(echo "$@" | jq -R '. | split(" ")')
    },
    version: {
      ref: $(echo $ref | jq -R .)
    }
  }" | ${resource_dir}/check | tee /dev/stderr
}

check_uri_from_paths_ignoring() {
  local uri=$1
  local ref=$2
  local paths=$3

  shift 3

  jq -n "{
    source: {
      uri: $(echo $uri | jq -R .),
      paths: [$(echo $paths | jq -R .)],
      ignore_paths: $(echo "$@" | jq -R '. | split(" ")')
    },
    version: {
      ref: $(echo $ref | jq -R .)
    }
  }" | ${resource_dir}/check | tee /dev/stderr
}

check_uri_with_tag_filter() {
  local uri=$1
  local tag_filter=$2
  jq -n "{
    source: {
      uri: $(echo $uri | jq -R .),
      tag_filter: $(echo $tag_filter | jq -R .)
    }
  }" | ${resource_dir}/check | tee /dev/stderr
}

check_uri_with_tag_filter_from_ref() {
  local uri=$1
  local ref=$2
  local tag_filter=$3
  jq -n "{
    source: {
      uri: $(echo $uri | jq -R .),
      tag_filter: $(echo $tag_filter | jq -R .)
    },
    version: {
      ref: $(echo $ref | jq -R .)
    }
  }" | ${resource_dir}/check | tee /dev/stderr
}

check_uri_with_revset_filter() {
  local uri=$1
  local revset_filter=$2
  jq -n "{
    source: {
      uri: $(echo $uri | jq -R .),
      revset_filter: $(echo $revset_filter | jq -R .)
    }
  }" | ${resource_dir}/check | tee /dev/stderr
}

check_uri_with_revset_filter_from_ref() {
  local uri=$1
  local ref=$2
  local revset_filter=$3
  jq -n "{
    source: {
      uri: $(echo $uri | jq -R .),
      revset_filter: $(echo $revset_filter | jq -R .)
    },
    version: {
      ref: $(echo $ref | jq -R .)
    }
  }" | ${resource_dir}/check | tee /dev/stderr
}

get_uri() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .)
    }
  }" | ${resource_dir}/in "$2" | tee /dev/stderr
}

get_uri_insecure() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .),
      skip_ssl_verification: true
    }
  }" | ${resource_dir}/in "$2" | tee /dev/stderr
}

get_uri_at_depth() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .)
    },
    params: {
      depth: $(echo $2 | jq -R .)
    }
  }" | ${resource_dir}/in "$3" | tee /dev/stderr
}

get_uri_with_submodules_at_depth() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .)
    },
    params: {
      depth: $(echo $2 | jq -R .),
      submodules: [$(echo $3 | jq -R .)],
    }
  }" | ${resource_dir}/in "$4" | tee /dev/stderr
}

get_uri_with_submodules_all() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .)
    },
    params: {
      depth: $(echo $2 | jq -R .),
      submodules: \"all\",
    }
  }" | ${resource_dir}/in "$3" | tee /dev/stderr
}

get_uri_at_ref() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .)
    },
    version: {
      ref: $(echo $2 | jq -R .)
    }
  }" | ${resource_dir}/in "$3" | tee /dev/stderr
}

get_uri_at_branch() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .),
      branch: $(echo $2 | jq -R .)
    }
  }" | ${resource_dir}/in "$3" | tee /dev/stderr
}


get_uri_omit_branch() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .),
      omit_branch: true
    }
  }" | ${resource_dir}/in "$2" | tee /dev/stderr
}

put_uri() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .),
      branch: \"default\"
    },
    params: {
      repository: $(echo $3 | jq -R .)
    }
  }" | ${resource_dir}/out "$2" | tee /dev/stderr
}

put_uri_no_branch() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .)
    },
    params: {
      repository: $(echo $3 | jq -R .)
    }
  }" | ${resource_dir}/out "$2" | tee /dev/stderr
}

put_uri_insecure() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .),
      branch: \"default\",
      skip_ssl_verification: true
    },
    params: {
      repository: $(echo $3 | jq -R .)
    }
  }" | ${resource_dir}/out "$2" | tee /dev/stderr
}

put_uri_with_only_tag() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .),
      branch: \"master\"
    },
    params: {
      repository: $(echo $3 | jq -R .),
      only_tag: true
    }
  }" | ${resource_dir}/out "$2" | tee /dev/stderr
}

put_uri_with_rebase() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .),
      branch: \"default\"
    },
    params: {
      repository: $(echo $3 | jq -R .),
      rebase: true
    }
  }" | ${resource_dir}/out "$2" | tee /dev/stderr
}

put_uri_with_rebase_and_race_conditions() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .),
      branch: \"default\"
    },
    params: {
      repository: $(echo $3 | jq -R .),
      rebase: true
    }
  }" | TEST_RACE_CONDITIONS=true ${resource_dir}/out "$2" | tee /dev/stderr
}

put_uri_with_tag() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .),
      branch: \"default\"
    },
    params: {
      tag: $(echo $3 | jq -R .),
      repository: $(echo $4 | jq -R .)
    }
  }" | ${resource_dir}/out "$2" | tee /dev/stderr
}

put_uri_with_tag_and_prefix() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .),
      branch: \"default\"
    },
    params: {
      tag: $(echo $3 | jq -R .),
      tag_prefix: $(echo $4 | jq -R .),
      repository: $(echo $5 | jq -R .)
    }
  }" | ${resource_dir}/out "$2" | tee /dev/stderr
}

put_uri_with_tag_and_annotation() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .),
      branch: \"default\"
    },
    params: {
      tag: $(echo $3 | jq -R .),
      annotate: $(echo $4 | jq -R .),
      repository: $(echo $5 | jq -R .)
    }
  }" | ${resource_dir}/out "$2" | tee /dev/stderr
}

put_uri_with_rebase_with_tag() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .),
      branch: \"default\"
    },
    params: {
      tag: $(echo $3 | jq -R .),
      repository: $(echo $4 | jq -R .),
      rebase: true
    }
  }" | ${resource_dir}/out "$2" | tee /dev/stderr
}

put_uri_with_rebase_with_tag_and_prefix() {
  jq -n "{
    source: {
      uri: $(echo $1 | jq -R .),
      branch: \"default\"
    },
    params: {
      tag: $(echo $3 | jq -R .),
      tag_prefix: $(echo $4 | jq -R .),
      repository: $(echo $5 | jq -R .),
      rebase: true
    }
  }" | ${resource_dir}/out "$2" | tee /dev/stderr
}
