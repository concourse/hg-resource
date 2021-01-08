package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/concourse/hg-resource/hg"
)

const cmdCheckName string = "check"

var cmdCheck = &Command{
	Name:    cmdCheckName,
	Run:     runCheck,
	NumArgs: 0,
}

func runCheck(args []string, params *JsonInput, outWriter io.Writer, errWriter io.Writer) int {
	repo := hg.Repository{
		Path:                filepath.Join(os.TempDir(), "hg-resource-repo-cache"),
		Branch:              params.Source.Branch,
		IncludePaths:        params.Source.IncludePaths,
		ExcludePaths:        params.Source.ExcludePaths,
		TagFilter:           params.Source.TagFilter,
		RevSetFilter:        params.Source.RevSetFilter,
		SkipSslVerification: params.Source.SkipSslVerification,
	}

	if len(repo.Branch) == 0 {
		repo.Branch = defaultBranch
	}

	if len(params.Source.Uri) == 0 {
		fmt.Fprintln(errWriter, "Repository URI must be provided")
		return 1
	}

	output, err := repo.CloneOrPull(params.Source.Uri)
	errWriter.Write(output)
	if err != nil {
		fmt.Fprintln(errWriter, err)
		return 1
	}

	if len(params.Version.Ref) == 0 {
		return writeLatestCommit(&repo, outWriter, errWriter)
	} else {
		return writeCommitsSince(params.Version.Ref, &repo, outWriter, errWriter)
	}
}

func writeLatestCommit(repo *hg.Repository, outWriter io.Writer, errWriter io.Writer) int {
	latestCommit, err := repo.GetLatestCommitId()
	if err != nil {
		fmt.Fprintln(errWriter, err)
		return 1
	}

	latestVersion := []Version{
		{
			Ref: latestCommit,
		},
	}

	_, err = WriteJson(outWriter, latestVersion)
	if err != nil {
		fmt.Fprintln(errWriter, err)
		return 1
	}
	return 0
}

func writeCommitsSince(parentCommit string, repo *hg.Repository, outWriter io.Writer, errWriter io.Writer) int {
	commits, err := repo.GetDescendantsOf(parentCommit)
	if err != nil {
		// commit id not found -- return latest commit as fallback
		return writeLatestCommit(repo, outWriter, errWriter)
	}

	commitList := make([]Version, len(commits))
	for i, commit := range commits {
		commitList[i] = Version{
			Ref: commit,
		}
	}

	_, err = WriteJson(outWriter, commitList)
	if err != nil {
		fmt.Fprintln(errWriter, err)
		return 1
	}

	return 0
}
