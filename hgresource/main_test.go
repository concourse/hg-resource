package main

import (
	"bytes"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gbytes"
)

var _ = Describe("Main", func() {
	var stderr *gbytes.Buffer
	var stdout *gbytes.Buffer
	Describe("Command line argument parsing", func() {
		emptyBuf := new(bytes.Buffer)
		Context("When run with 'hgresource' as application name", func() {
			Context("without any subcommand", func() {
				BeforeEach(func() {
					stderr = gbytes.NewBuffer()
					stdout = gbytes.NewBuffer()
					args := []string{"hgresource"}
					run(args, emptyBuf, stdout, stderr)
				})

				It("should print the list of subcommands", func() {
					Expect(stderr).To(gbytes.Say("Usage: hgresource <check|in|out> [arguments]"))
				})
			})

			Context("with a subcommand", func() {
				BeforeEach(func() {
					stderr = gbytes.NewBuffer()
					stdout = gbytes.NewBuffer()
					args := []string{"hgresource", "in"}
					run(args, emptyBuf, stdout, stderr)
				})

				It("should run the subcommand", func() {
					Expect(stderr).To(gbytes.Say("Usage: hgresource in <path/to/destination>"))
				})
			})
		})

		Context("When run with a multi-call alias as application name", func() {
			BeforeEach(func() {
				stderr = gbytes.NewBuffer()
				stdout = gbytes.NewBuffer()
				args := []string{"in"}
				run(args, emptyBuf, stdout, stderr)
			})

			It("should run the corresponding subcommand", func() {
				Expect(stderr).To(gbytes.Say("Usage: in <path/to/destination>"))
			})
		})
	})
})
