package hg

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path"
	"strings"
	"time"
)

type Repository struct {
	Path                string
	Branch              string
	IncludePaths        []string
	ExcludePaths        []string
	TagFilter           string
	RevSetFilter        string
	SkipSslVerification bool
}

type CommitProperty struct {
	Name  string `json:"name"`
	Value string `json:"value"`
	Type  string `json:"type,omitempty"`
}

type HgChangeset struct {
	Rev       int      `json:"rev"`
	Node      string   `json:"node"`
	Branch    string   `json:"branch"`
	Phase     string   `json:"phase"`
	User      string   `json:"user"`
	Date      []int64  `json:"date"`
	Desc      string   `json:"desc"`
	Bookmarks []string `json:"bookmarks"`
	Tags      []string `json:"tags"`
	Parents   []string `json:"parents"`
	Topic     []string `json:"topic"`
}

func (self *Repository) CloneOrPull(sourceUri string) ([]byte, error) {
	if len(self.Path) == 0 {
		return []byte{}, fmt.Errorf("CloneOrPull: repository path must be set")
	}

	if len(self.Branch) == 0 {
		return []byte{}, fmt.Errorf("CloneOrPull: branch must be set")
	}

	dirInfo, errIfNotExists := os.Stat(path.Join(self.Path, ".hg"))
	if errIfNotExists != nil || !dirInfo.IsDir() {
		return self.clone(sourceUri)
	} else {
		return self.pull()
	}
}

func (self *Repository) clone(sourceUri string) (output []byte, err error) {
	_, output, err = self.run("clone", []string{
		"-q",
		"--branch", self.Branch,
		sourceUri,
		self.Path,
	})
	if err != nil {
		err = fmt.Errorf("Error cloning repository from %s: %s", sourceUri, err)
	}

	return
}

func (self *Repository) pull() (output []byte, err error) {
	_, output, err = self.run("pull", []string{
		"-q",
		"--cwd", self.Path,
	})
	if err != nil {
		err = fmt.Errorf("Error pulling changes from repository: %s", err)
		return
	}

	_, checkoutOutput, err := self.run("checkout", []string{
		"-q",
		"--cwd", self.Path,
		"--clean",
		"--rev", self.Branch,
	})
	output = append(output, checkoutOutput...)
	if err != nil {
		err = fmt.Errorf("Error updating working directory to tip: %s", err)
	}

	return
}

func (self *Repository) PullWithRebase(sourceUri string, branch string) (output []byte, err error) {
	_, output, err = self.run("pull", []string{
		"-q",
		"--cwd", self.Path,
		"--config", "extensions.rebase=",
		"--config", "paths.push-target=" + sourceUri,
		"--rebase",
		"--branch", branch,
		"push-target",
	})
	if err != nil {
		err = fmt.Errorf("Error pulling/rebasing from: %s: %s", sourceUri, err)
	}
	return
}

// Clones sourceUri into the repository and truncates all history after the given commit,
// making it the new tip. After truncating, we can add a tag commit at tip, and then push
// the whole known branch (... -> given commit -> tag commit == tip) to another repository.
func (self *Repository) CloneAtCommit(sourceUri string, commitId string) (output []byte, err error) {
	_, output, err = self.run("clone", []string{
		"-q",
		"--rev", commitId,
		sourceUri,
		self.Path,
	})
	if err != nil {
		err = fmt.Errorf("Error cloning repository %s@%s: %s", sourceUri, commitId, err)
	}

	return
}

// Makes the repository rebaseable. See `hg help phases`.
func (self *Repository) SetDraftPhase() (output []byte, err error) {
	_, output, err = self.run("phase", []string{
		"--cwd", self.Path,
		"--force",
		"--draft",
	})
	if err != nil {
		err = fmt.Errorf("Error setting repo phase to draft: %s", err)
	}

	return
}

func (self *Repository) Push(destUri string, branch string) (output []byte, err error) {
	_, output, err = self.run("push", []string{
		"--cwd", self.Path,
		"--config", "paths.push-target=" + destUri,
		"--branch", branch,
		"push-target",
	})
	if err != nil {
		err = fmt.Errorf("Error pushing to %s: %s", destUri, err)
	}

	return
}

// Tags a commit. Expects to be run only at tip!
func (self *Repository) Tag(tagValue string) (output []byte, err error) {
	_, output, err = self.run("tag", []string{
		"--cwd", self.Path,
		tagValue,
	})
	if err != nil {
		err = fmt.Errorf("Error tagging current commit: %s", err)
	}

	return
}

func (self *Repository) Delete() error {
	err := os.RemoveAll(self.Path)
	if err != nil {
		return fmt.Errorf("Error deleting repository: %s", err)
	}

	return nil
}

func (self *Repository) Checkout(commitId string) (output []byte, err error) {
	_, output, err = self.run("checkout", []string{
		"-q",
		"--cwd", self.Path,
		"--clean",
		"--rev", commitId,
	})
	if err != nil {
		err = fmt.Errorf("Error checking out %s: %s", commitId, err)
	}

	return
}

func (self *Repository) Purge() (output []byte, err error) {
	_, output, err = self.run("purge", []string{
		"--config", "extensions.purge=",
		"--cwd", self.Path,
		"--all",
	})
	if err != nil {
		err = fmt.Errorf("Error purging repository: %s", err)
	}

	return
}

func (self *Repository) GetLatestCommitId() (output string, err error) {
	branch := escapePath(self.Branch)
	include := self.makeIncludeQueryFragment()
	exclude := self.makeExcludeQueryFragment()
	revSetFilter := self.maybeRevSetFilter()
	revSet := fmt.Sprintf("last((((%s) - (%s)) & branch('%s') & %s) - desc('[ci skip]'))", include, exclude, branch, revSetFilter)

	_, outBytes, err := self.run("log", []string{
		"--cwd", self.Path,
		"--rev", revSet,
		"--template", "{node}",
	})
	output = string(outBytes)
	if err != nil {
		err = fmt.Errorf("Error getting latest commit id: %s", err)
	}

	return
}

func (self *Repository) GetCurrentCommitId() (output string, err error) {
	_, outBytes, err := self.run("log", []string{
		"--cwd", self.Path,
		"--rev", ".",
		"--template", "{node}",
	})
	output = string(outBytes)
	if err != nil {
		err = fmt.Errorf("Error getting current commit id: %s", err)
	}

	return
}

func (self *Repository) GetDescendantsOf(commitId string) ([]string, error) {
	branch := escapePath(self.Branch)
	include := self.makeIncludeQueryFragment()
	exclude := self.makeExcludeQueryFragment()
	revSetFilter := self.maybeRevSetFilter()
	revSet := fmt.Sprintf("(descendants(%s) - %s) & branch('%s') & %s & ((%s) - (%s)) - desc('[ci skip]')",
		commitId, commitId, branch, revSetFilter, include, exclude)

	_, outBytes, err := self.run("log", []string{
		"--cwd", self.Path,
		"--rev", revSet,
		"--template", "{node}\n",
	})

	output := string(outBytes)
	if err != nil {
		return []string{}, fmt.Errorf("Error getting descendant commits of %s: %s\n%s", commitId, err, output)
	}

	trimmed := strings.Trim(output, "\n\r ")
	if len(trimmed) == 0 {
		return []string{}, nil
	}

	commits := strings.Split(trimmed, "\n")
	return commits, nil
}

func (self *Repository) maybeRevSetFilter() string {
	var filters []string
	if len(self.TagFilter) > 0 {
		filters = append(filters,
			"tag('re:"+escapePath(self.TagFilter)+"')")
	}
	if len(self.RevSetFilter) > 0 {
		filters = append(filters,
			"("+escapePath(self.RevSetFilter)+")")
	}
	if len(filters) == 0 {
		return "all()"
	}
	return strings.Join(filters, " & ")
}

func (self *Repository) Metadata(commitId string) (metadata []CommitProperty, err error) {
	_, outBytes, err := self.run("log", []string{
		"--cwd", self.Path,
		"--rev", commitId,
		"--template", "json",
	})
	if err != nil {
		err = fmt.Errorf("Error getting metadata for commit %s: %s\n%s", commitId, err, string(outBytes))
	}

	metadata, err = parseMetadata(outBytes)

	_, outBytes, err = self.run("log", []string{
		"--cwd", self.Path,
		"--rev", commitId,
		"--template", "{topics}",
	})
	if err != nil {
		err = fmt.Errorf("Error getting topic for commit %s: %s\n%s", commitId, err, string(outBytes))
	}

	metadata = append(metadata,
		CommitProperty{
			Name:  "topic",
			Value: string(outBytes),
		})

	return
}

func parseHgTime(hgTime []int64) (parsedTime time.Time, err error) {
	if len(hgTime) != 2 {
		err = fmt.Errorf("parseHgTime: expected slice hgTime to have 2 elements")
	}
	utcEpoch := hgTime[0]
	offset := hgTime[1]

	utcTime := time.Unix(utcEpoch, 0)

	// for some reason, mercurial uses the inverse sign on the offset
	zone := time.FixedZone("internet time", -1*int(offset))

	parsedTime = utcTime.In(zone)
	return
}

func timeToIso8601(timestamp time.Time) string {
	return timestamp.Format("2006-01-02 15:04:05 -0700")
}

func (commit *HgChangeset) toCommitProperties() (metadata []CommitProperty, err error) {
	timestamp, err := parseHgTime(commit.Date)
	if err != nil {
		return
	}

	metadata = append(metadata,
		CommitProperty{
			Name:  "commit",
			Value: commit.Node,
		},
		CommitProperty{
			Name:  "author",
			Value: commit.User,
		},
		CommitProperty{
			Name:  "author_date",
			Value: timeToIso8601(timestamp),
			Type:  "time",
		},
		CommitProperty{
			Name:  "message",
			Value: commit.Desc,
			Type:  "message",
		},
		CommitProperty{
			Name:  "tags",
			Value: strings.Join(commit.Tags, ", "),
		},
		CommitProperty{
			Name:  "bookmarks",
			Value: strings.Join(commit.Bookmarks, ", "),
		},
	)

	return
}

func parseMetadata(hgJsonOutput []byte) (metadata []CommitProperty, err error) {
	commits := []HgChangeset{}
	err = json.Unmarshal(hgJsonOutput, &commits)
	if err != nil {
		return
	}

	if len(commits) != 1 {
		err = fmt.Errorf("parseMetadata: expected 1 commit, found %d", len(commits))
		return
	}

	metadata, err = commits[0].toCommitProperties()
	return
}

func (self *Repository) run(command string, args []string) (cmd *exec.Cmd, output []byte, err error) {
	hgArgs := make([]string, 1, len(args)+1)
	hgArgs[0] = command

	if self.SkipSslVerification && commandTakesInsecureOption(command) {
		hgArgs = append(hgArgs, "--insecure")
	}
	hgArgs = append(hgArgs, args...)

	cmd = exec.Command("hg", hgArgs...)

	output, err = cmd.CombinedOutput()
	return
}

func commandTakesInsecureOption(command string) bool {
	eligibleCommands := []string{
		"clone",
		"pull",
		"push",
	}
	for _, eligibleCommand := range eligibleCommands {
		if command == eligibleCommand {
			return true
		}
	}
	return false
}

func (self *Repository) makeIncludeQueryFragment() string {
	if len(self.IncludePaths) == 0 {
		return "all()"
	} else {
		return unionOfPaths(self.IncludePaths)
	}
}

func (self *Repository) makeExcludeQueryFragment() string {
	if len(self.ExcludePaths) == 0 {
		return "not all()"
	} else {
		return unionOfPaths(self.ExcludePaths)
	}
}

func unionOfPaths(paths []string) string {
	escapedPaths := make([]string, len(paths))
	for i, path := range paths {
		escapedPaths[i] = "file('re:" + escapePath(path) + "')"
	}
	return strings.Join(escapedPaths, "|")
}

func escapePath(path string) string {
	backslashesEscaped := strings.Replace(path, "\\", "\\\\\\\\", -1)
	quotesEscaped := strings.Replace(backslashesEscaped, "'", "\\'", -1)
	return quotesEscaped
}
