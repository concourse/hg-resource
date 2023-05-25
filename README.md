# Mercurial Resource

Tracks the commits in a [Mercurial](https://www.mercurial-scm.org/) repository.


## Source Configuration

* `uri`: *Required.* The location of the repository.

* `branch`: The branch to track, defaults to `default`.

* `omit_branch`: If set to true, the entire repository history will be cloned. Defaults to false.

* `private_key`: *Optional.* Private key to use when pulling/pushing.
    Example:
    ```
    private_key: |
      -----BEGIN RSA PRIVATE KEY-----
      MIIEowIBAAKCAQEAtCS10/f7W7lkQaSgD/mVeaSOvSF9ql4hf/zfMwfVGgHWjj+W
      <Lots more text>
      DWiJL+OFeg9kawcUL6hQ8JeXPhlImG6RTUffma9+iGQyyBMCGd1l
      -----END RSA PRIVATE KEY-----
    ```

* `paths`: *Optional.* If specified (as a list of regular expressions), only changes
  to the specified files will yield new versions from `check`.

* `ignore_paths`: *Optional.* The inverse of `paths`; changes to the specified
  files are ignored.

  Note that if you want to push commits that change these files via a `put`,
  the commit will still be "detected", as [`check` and `put` both introduce
  versions](https://concourse-ci.org/pipeline-mechanics.html#collecting-versions).
  To avoid this you should define a second resource that you use for commits
  that change files that you don't want to feed back into your pipeline - think
  of one as read-only (with `ignore_paths`) and one as write-only (which
  shouldn't need it).

* `skip_ssl_verification`: *Optional.* Skips git ssl verification by exporting
  `GIT_SSL_NO_VERIFY=true`.

* `tag_filter`: *Optional*. If specified, the resource will only detect commits
  that have a tag matching the specified regular expression.

* `revset_filter`: *Optional*. If specified, the resource will only detect commits
  that matches the specified revset expression
  (see https://www.mercurial-scm.org/repo/hg/help/revsets).

### Example

Resource configuration for a private repo:

``` yaml
resources:
- name: source-code
  type: hg
  source:
    uri: ssh://user@hg.example.com/my-repo
    branch: default
    private_key: |
      -----BEGIN RSA PRIVATE KEY-----
      MIIEowIBAAKCAQEAtCS10/f7W7lkQaSgD/mVeaSOvSF9ql4hf/zfMwfVGgHWjj+W
      <Lots more text>
      DWiJL+OFeg9kawcUL6hQ8JeXPhlImG6RTUffma9+iGQyyBMCGd1l
      -----END RSA PRIVATE KEY-----
```

Pushing local commits to the repo:

``` yaml
- get: some-other-repo
- put: source-code
  params: {repository: some-other-repo}
```


## Behavior

### `check`: Check for new commits.

The repository is cloned (or pulled if already present), and any commits
made after the given version are returned. If no version is given, the ref
for the head of the branch is returned.

Any commits that contain the string `[ci skip]` will be ignored. This
allows you to commit to your repository without triggering a new version.

### `in`: Clone the repository, at the given ref.

Clones the repository to the destination, and locks it down to a given ref.
Returns the resulting ref as the version.

Subrepositories are initialized and updated recursively, as Mercurial does
by default.


### `out`: Push to a repository.

Push the checked-out reference to the source's URI and branch. If a
fast-forward for the branch is not possible and the `rebase` parameter is not
provided, the push will fail. The `tag` option can only be used in
combination with `rebase`, as tagging in Mercurial involves adding a new
commit. Specifically, `out` clones the repository and strips all descendants
of the checked-out reference, and then adds the tag commit as the new tip.


#### Parameters

* `repository`: *Required.* The path of the repository to push to the source.

* `rebase`: *Optional.* If pushing fails with non-fast-forward, continuously
  attempt rebasing and pushing.

* `tag`: *Optional, requires `rebase`* If this is set then the checked-out reference will be
  tagged. The value should be a path to a file containing the name of the tag.

* `tag_prefix`: *Optional.* If specified, the tag read from the file will be
prepended with this string. This is useful for adding `v` in front of
version numbers.

## Development

### Prerequisites

* golang is *required* - version 1.9.x is tested; earlier versions may also
  work.
* docker is *required* - version 17.06.x is tested; earlier versions may also
  work.
* godep is used for dependency management of the golang packages.

### Running the tests

The tests have been embedded with the `Dockerfile`; ensuring that the testing
environment is consistent across any `docker` enabled platform. When the docker
image builds, the test are run inside the docker container, on failure they
will stop the build.

Run the tests with the following command:

```sh
docker build -t hg-resource --target tests --build-arg base_image=paketobuildpacks/run-jammy-base:latest .
```

### Contributing

Please make all pull requests to the `master` branch and ensure tests pass
locally.
