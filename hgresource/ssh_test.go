package main

import (
	"os"
	"strconv"
	"syscall"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

func processExists(pid int) bool {
	proc, _ := os.FindProcess(pid)
	err := proc.Signal(syscall.Signal(0))
	// err could also be "permission denied", but for this test it's good enough
	return err == nil
}

var _ = Describe("Ssh", func() {
	Context("When starting ssh-agent", func() {
		vars := "SSH_AGENT_PID=123; export SSH_AGENT_PID;\nFOO=bar; export FOO;\nANSWER=42\n"
		BeforeEach(func() {
			os.Setenv("SSH_AGENT_PID", "")
			os.Setenv("FOO", "")
			os.Setenv("ANSWER", "")
		})

		It("sets the environment variables ssh-agent prints to STDOUT", func() {
			setEnvironmentVariablesFromString(vars)

			Expect(os.Getenv("SSH_AGENT_PID")).To(Equal("123"))
			Expect(os.Getenv("FOO")).To(Equal("bar"))
			Expect(os.Getenv("ANSWER")).To(Equal("42"))
		})

		It("can start and kill the agent", func() {
			err := startSshAgent()
			Expect(err).To(BeNil())

			Expect(os.Getenv("SSH_AGENT_PID")).ToNot(BeEmpty())

			pid, err := strconv.Atoi(os.Getenv("SSH_AGENT_PID"))
			Expect(err).To(BeNil())

			err = killSshAgent()
			Expect(err).To(BeNil())

			Eventually(func() bool {
				return processExists(pid)
			}).Should(BeFalse())
		})
	})
})
