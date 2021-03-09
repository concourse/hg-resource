package main

import (
	"bytes"
	"errors"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path"
	"strconv"
	"strings"

	"golang.org/x/crypto/ssh"
)

const (
	sshClientConfig             = "StrictHostKeyChecking no\nLogLevel quiet\n"
	sshClientConfigFileRelative = ".ssh/config"
)

var ErrPassphraseUnsupported = errors.New("Private keys with passphrases are not supported.")

// Writes SSH private key to a file in $TMPDIR or /tmp, starts ssh-agent and
// loads the key
func loadSshPrivateKey(privateKeyPem string) error {
	_, err := ssh.ParsePrivateKey([]byte(privateKeyPem))
	if err != nil {
		var passphraseError *ssh.PassphraseMissingError
		if errors.As(err, &passphraseError) {
			return ErrPassphraseUnsupported
		}

		return fmt.Errorf("parse private key: %w", err)
	}

	err = startSshAgent()
	if err != nil {
		return err
	}

	err = addSshKey(privateKeyPem)
	if err != nil {
		return err
	}

	homeDir, err := os.UserHomeDir()
	if err != nil {
		return err
	}

	sshClientConfigFile := path.Join(homeDir, sshClientConfigFileRelative)

	err = mkSSHDir(sshClientConfigFile)
	if err != nil {
		return err
	}
	err = ioutil.WriteFile(sshClientConfigFile, []byte(sshClientConfig), 0600)
	if err != nil {
		return err
	}

	return nil
}

func mkSSHDir(sshClientConfigFile string) error {
	sshDir := path.Dir(sshClientConfigFile)
	_, pathErr := os.Stat(sshDir)
	if pathErr != nil {
		err := os.MkdirAll(sshDir, 0700)
		if err != nil {
			return fmt.Errorf("could not create .ssh dir: %s", err)
		}
		err = os.Chmod(sshDir, 0700)
		if err != nil {
			return fmt.Errorf("failed setting rights: %s", err)
		}
	}
	return nil
}

func addSshKey(privateKeyPem string) error {
	stderr := new(bytes.Buffer)
	addCmd := exec.Command("ssh-add", "-")
	addCmd.Stderr = stderr
	addCmd.Stdin = bytes.NewBufferString(privateKeyPem)

	err := addCmd.Run()
	if err != nil {
		errMsg := stderr.String()
		if len(errMsg) > 0 {
			return fmt.Errorf("ssh-add: %s", errMsg)
		} else {
			return fmt.Errorf("ssh-add: %w", err)
		}
	}

	return nil
}

func startSshAgent() error {
	killSshAgent()

	stdout := new(bytes.Buffer)
	agentCmd := exec.Command("ssh-agent")
	agentCmd.Stdout = stdout

	err := agentCmd.Run()
	if err != nil {
		return fmt.Errorf("ssh-agent: %w", err)
	}

	setEnvironmentVariablesFromString(stdout.String())
	return nil
}

func killSshAgent() error {
	pidString := os.Getenv("SSH_AGENT_PID")
	if len(pidString) == 0 {
		return nil
	}

	pid, err := strconv.Atoi(pidString)
	if err != nil {
		return fmt.Errorf("kill ssh-agent: SSH_AGENT_PID not an integer, but: %s", pidString)
	}

	proc, err := os.FindProcess(pid)
	if err != nil {
		return err
	}

	err = proc.Kill()
	if err != nil {
		return err
	}

	return nil
}

func setEnvironmentVariablesFromString(multiLine string) {
	lines := strings.Split(multiLine, "\n")
	for _, line := range lines {
		// we don't support any kind of quoting or escaping
		lineBeforeSemicolon := strings.SplitN(line, ";", 2)
		keyValue := strings.SplitN(lineBeforeSemicolon[0], "=", 2)
		if len(keyValue) == 2 {
			os.Setenv(keyValue[0], keyValue[1])
		}
	}
}
