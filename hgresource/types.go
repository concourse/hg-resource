package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"github.com/concourse/hg-resource/hg"
	"io"
)

type Source struct {
	Uri                 string   `json:"uri"`
	PrivateKey          string   `json:"private_key"`
	IncludePaths        []string `json:"paths"`
	ExcludePaths        []string `json:"ignore_paths"`
	Branch              string   `json:"branch"`
	OmitBranch          bool     `json:"omit_branch"`
	TagFilter           string   `json:"tag_filter"`
	RevSetFilter        string   `json:"revset_filter"`
	SkipSslVerification bool     `json:"skip_ssl_verification"`
}

type Version struct {
	Ref string `json:"ref"`
}

type Params struct {
	Repository string `json:"repository"`
	Tag        string `json:"tag"`
	TagPrefix  string `json:"tag_prefix"`
	Rebase     bool   `json:"rebase"`
}

type JsonInput struct {
	Source  Source  `json:"source"`
	Version Version `json:"version"`
	Params  Params  `json:"params"`
}

type JsonOutput struct {
	Metadata []hg.CommitProperty `json:"metadata"`
	Version  Version             `json:"version"`
}

func parseInput(inReader io.Reader) (*JsonInput, error) {
	bytes, err := readAllBytes(inReader)
	if err != nil {
		return nil, err
	}

	params := JsonInput{}
	json.Unmarshal(bytes, &params)
	return &params, nil
}

func readAllBytes(reader io.Reader) ([]byte, error) {
	buf := new(bytes.Buffer)
	_, err := buf.ReadFrom(reader)

	if err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func WriteJson(outWriter io.Writer, object interface{}) (n int, err error) {
	output, err := json.Marshal(object)
	if err != nil {
		return n, fmt.Errorf("Error serializing JSON response: %s", err)
	}

	n, err = outWriter.Write(output)
	if err != nil {
		return n, fmt.Errorf("Error writing JSON to io.Writer: %s", err)
	}

	outWriter.Write([]byte("\n"))
	n++
	return
}
