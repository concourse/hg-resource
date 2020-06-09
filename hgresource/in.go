package main

import (
	"fmt"
	"github.com/concourse/hg-resource/hg"
	"io"
)

const cmdInName string = "in"

var cmdIn = &Command{
	Name:    cmdInName,
	Run:     runIn,
	NumArgs: 1,
	Usage:   inUsage,
}

func runIn(args []string, params *JsonInput, outWriter io.Writer, errWriter io.Writer) int {
	destination := args[0]

	repo := &hg.Repository{
		Path:                destination,
		Branch:              params.Source.Branch,
		OmitBranch:          params.Source.OmitBranch,
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

	var commitId string
	if len(params.Version.Ref) == 0 {
		commitId = "tip"
	} else {
		commitId = params.Version.Ref
	}

	output, err := repo.CloneOrPull(params.Source.Uri)
	errWriter.Write(output)
	if err != nil {
		fmt.Fprintln(errWriter, err)
		return 1
	}

	output, err = repo.Checkout(commitId)
	errWriter.Write(output)
	if err != nil {
		fmt.Fprintln(errWriter, err)
		return 1
	}

	output, err = repo.Purge()
	errWriter.Write(output)
	if err != nil {
		fmt.Fprintln(errWriter, err)
		return 1
	}

	jsonOutput, err := getJsonOutputForCurrentCommit(repo)
	if err != nil {
		fmt.Fprintln(errWriter, err)
		return 1
	}
	WriteJson(outWriter, jsonOutput)
	return 0
}

func inUsage(appName string, err io.Writer) {
	errMsg := fmt.Sprintf("Usage: %s <path/to/destination>", appName)
	err.Write([]byte(errMsg))
}
