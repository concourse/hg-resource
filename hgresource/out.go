package main

import (
	"fmt"
	"io"
	"io/ioutil"
	"os"
	"path"
	"strings"
	"time"

	"github.com/concourse/hg-resource/hg"
)

const cmdOutName string = "out"

var cmdOut = &Command{
	Name:    cmdOutName,
	Run:     runOut,
	NumArgs: 1,
	Usage:   outUsage,
}

type PushParams struct {
	Branch     string
	SourcePath string
	DestUri    string
	TagValue   string
	Rebase     bool
}

const maxRebaseRetries = 10

func runOut(args []string, input *JsonInput, outWriter io.Writer, errWriter io.Writer) int {
	source := args[0]

	validatedParams, err := validateInput(input, source)
	if err != nil {
		fmt.Fprintln(errWriter, err)
		return 1
	}

	sourceRepo := &hg.Repository{
		Path:                validatedParams.SourcePath,
		Branch:              validatedParams.Branch,
		SkipSslVerification: input.Source.SkipSslVerification,
	}

	commitId, err := sourceRepo.GetCurrentCommitId()
	if err != nil {
		fmt.Fprintln(errWriter, err)
		return 1
	}

	// clone source into temporary directory, up to the current (not latest) commit id, thus truncating history
	tempRepo, tempRepoCleanup, err := cloneAtCommitIntoTempDir(sourceRepo, commitId, errWriter)
	defer tempRepoCleanup(errWriter)

	var jsonOutput JsonOutput
	if validatedParams.Rebase {
		jsonOutput, err = rebaseAndPush(tempRepo, validatedParams, maxRebaseRetries, errWriter)
		if err != nil {
			fmt.Fprintln(errWriter, err)
			return 1
		}

	} else {
		output, err := tempRepo.Push(validatedParams.DestUri, validatedParams.Branch)
		errWriter.Write(output)
		if err != nil {
			fmt.Fprintln(errWriter, err)
			return 1
		}

		jsonOutput, err = getJsonOutputForCurrentCommit(tempRepo)
		if err != nil {
			fmt.Fprintf(errWriter, "Error retrieving metadata from temp repository: %s", err)
			return 1
		}
	}

	WriteJson(outWriter, jsonOutput)
	return 0
}

func rebaseAndPush(tempRepo *hg.Repository, params PushParams, maxRetries int, errWriter io.Writer) (jsonOutput JsonOutput, err error) {
	for pushAttempt := 0; pushAttempt < maxRetries; pushAttempt++ {
		var output []byte
		fmt.Fprintf(errWriter, "rebasing, attempt %d/%d...\n", pushAttempt+1, maxRetries)
		output, err = tempRepo.PullWithRebase(params.DestUri, params.Branch)
		errWriter.Write(output)
		if err != nil {
			return
		}

		jsonOutput, err = getJsonOutputForCurrentCommit(tempRepo)
		if err != nil {
			return
		}

		if len(params.TagValue) > 0 {
			output, err = tempRepo.Tag(params.TagValue)
			errWriter.Write(output)
			if err != nil {
				return
			}
		}

		if len(os.Getenv("TEST_RACE_CONDITIONS")) > 0 {
			time.Sleep(2 * time.Second)
		}

		output, err = tempRepo.Push(params.DestUri, params.Branch)
		errWriter.Write(output)
		if err == nil {
			fmt.Fprintln(errWriter, "pushed")
			return
		}
		if isNonFastForwardError(string(output)) {
			continue
		}
		fmt.Fprintln(errWriter, "failed with non-rebase error")
		return
	}
	err = fmt.Errorf("Error: too many retries")
	return
}

func getJsonOutputForCurrentCommit(repo *hg.Repository) (output JsonOutput, err error) {
	var commitId string
	commitId, err = repo.GetCurrentCommitId()
	if err != nil {
		err = fmt.Errorf("Error getting rebased commit id from temp repo: %s", err)
		return
	}

	var metadata []hg.CommitProperty
	metadata, err = repo.Metadata(commitId)
	if err != nil {
		err = fmt.Errorf("Error getting metadata from rebased commit in temp repo: %s", err)
		return
	}

	output = JsonOutput{
		Version: Version{
			Ref: commitId,
		},
		Metadata: metadata,
	}
	return
}

func isNonFastForwardError(hgStderr string) bool {
	lines := strings.Split(hgStderr, "\n")
	for _, line := range lines {
		if strings.HasPrefix(line, "abort: push creates new remote head") {
			return true
		}
	}
	return false
}

func cloneAtCommitIntoTempDir(sourceRepo *hg.Repository, commitId string, errWriter io.Writer) (tempRepo *hg.Repository, cleanupFunc func(io.Writer), err error) {
	tempRepoDir, err := getTempDirForCommit(commitId)
	if err != nil {
		return
	}
	tempRepo = &hg.Repository{
		Path:                tempRepoDir,
		Branch:              sourceRepo.Branch,
		SkipSslVerification: sourceRepo.SkipSslVerification,
	}
	cleanupFunc = func(errWriter io.Writer) {
		envOverride := os.Getenv("TEST_REPO_AT_REF_DIR")
		if envOverride != tempRepo.Path {
			err = tempRepo.Delete()
			if err != nil {
				fmt.Fprintln(errWriter, err)
			}
		}
	}

	output, err := tempRepo.CloneAtCommit(sourceRepo.Path, commitId)
	errWriter.Write(output)
	if err != nil {
		return
	}

	output, err = tempRepo.SetDraftPhase()
	errWriter.Write(output)
	if err != nil {
		return
	}
	return
}

func validateInput(input *JsonInput, sourceDir string) (validated PushParams, err error) {
	requiredParams := []string{
		input.Source.Uri, "uri in resources[repo].source",
		input.Params.Repository, "repository in <put step>.params",
	}
	for i, value := range requiredParams {
		if len(value) == 0 {
			err = fmt.Errorf("Error: invalid configuration (missing %s)", requiredParams[i+1])
			return
		}
	}
	validated.DestUri = input.Source.Uri
	validated.Rebase = input.Params.Rebase

	validated.Branch = input.Source.Branch
	if len(validated.Branch) == 0 {
		validated.Branch = defaultBranch
	}
	validated.SourcePath = path.Join(sourceDir, input.Params.Repository)

	if len(input.Params.Tag) > 0 {
		if !validated.Rebase {
			err = fmt.Errorf("Error: tag parameter requires rebase option: tagging in Mercurial works by inserting a commit")
			return
		}

		tagFile := path.Join(sourceDir, input.Params.Tag)
		var tagFileInfo os.FileInfo
		tagFileInfo, err = os.Stat(tagFile)
		if err != nil || tagFileInfo.IsDir() {
			err = fmt.Errorf("Error: tag file '%s' does not exist: %s", tagFile, err)
			return
		}

		var tagFileContent []byte
		tagFileContent, err = ioutil.ReadFile(tagFile)
		if err != nil {
			err = fmt.Errorf("Error reading tag file '%s': %s\n", tagFile, err)
			return
		}
		validated.TagValue = input.Params.TagPrefix + string(tagFileContent)
	}

	return
}

func getTempDirForCommit(commitId string) (string, error) {
	envOverride := os.Getenv("TEST_REPO_AT_REF_DIR")
	if len(envOverride) > 0 {
		return envOverride, nil
	}

	parentDir := os.TempDir()
	prefix := "hg-repo-at-" + commitId
	dirForCommit, err := ioutil.TempDir(parentDir, prefix)
	if err != nil {
		return "", fmt.Errorf("Unable to create temp dir to clone into: %s", err)
	}
	return dirForCommit, nil
}

func outUsage(appName string, err io.Writer) {
	errMsg := fmt.Sprintf("Usage: %s <path/to/source>", appName)
	err.Write([]byte(errMsg))
}
