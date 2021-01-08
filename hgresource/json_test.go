package main

import (
	"bytes"
	"encoding/json"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

var _ = Describe("Json", func() {
	Context("When parsing check input", func() {
		var buf *bytes.Buffer
		checkInput := `
			{
				"source": {
					"uri": "https://github.com/github/example",
					"private_key": "xyz",
					"paths": [
						"path/1",
						"path/2",
						"path/3"
					],
					"ignore_paths": [
						"path/4",
						"path/5",
						"path/6"
					],
					"branch": "a_branch",
					"tag_filter": "staging",
					"revset_filter": "public()",
					"skip_ssl_verification": true
				},
				"version": {
					"ref": "abc"
				}

			}

		`

		BeforeEach(func() {
			buf = new(bytes.Buffer)
			buf.Write([]byte(checkInput))
		})

		It("encoding/json deserialize everything", func() {
			var result JsonInput
			json.Unmarshal([]byte(checkInput), &result)
			Expect(result.Source.Uri).To(Equal("https://github.com/github/example"))
			Expect(result.Source.PrivateKey).To(Equal("xyz"))
			Expect(result.Source.IncludePaths).To(HaveLen(3))
			Expect(result.Source.IncludePaths[0]).To(Equal("path/1"))
			Expect(result.Source.IncludePaths[1]).To(Equal("path/2"))
			Expect(result.Source.IncludePaths[2]).To(Equal("path/3"))
			Expect(result.Source.ExcludePaths).To(HaveLen(3))
			Expect(result.Source.ExcludePaths[0]).To(Equal("path/4"))
			Expect(result.Source.ExcludePaths[1]).To(Equal("path/5"))
			Expect(result.Source.ExcludePaths[2]).To(Equal("path/6"))
			Expect(result.Source.Branch).To(Equal("a_branch"))
			Expect(result.Source.SkipSslVerification).To(BeTrue())
			Expect(result.Version.Ref).To(Equal("abc"))
		})

		It("readAllBytes reads all bytes", func() {
			bytes, err := readAllBytes(buf)

			Expect(err).To(BeNil())
			Expect(bytes).To(Equal([]byte(checkInput)))
		})

		It("parseInput can deserialize everything", func() {
			result, err := parseInput(buf)

			Expect(err).To(BeNil())
			Expect(result.Source.Uri).To(Equal("https://github.com/github/example"))
			Expect(result.Source.PrivateKey).To(Equal("xyz"))
			Expect(result.Source.IncludePaths).To(HaveLen(3))
			Expect(result.Source.IncludePaths[0]).To(Equal("path/1"))
			Expect(result.Source.IncludePaths[1]).To(Equal("path/2"))
			Expect(result.Source.IncludePaths[2]).To(Equal("path/3"))
			Expect(result.Source.ExcludePaths).To(HaveLen(3))
			Expect(result.Source.ExcludePaths[0]).To(Equal("path/4"))
			Expect(result.Source.ExcludePaths[1]).To(Equal("path/5"))
			Expect(result.Source.ExcludePaths[2]).To(Equal("path/6"))
			Expect(result.Source.Branch).To(Equal("a_branch"))
			Expect(result.Source.SkipSslVerification).To(BeTrue())
			Expect(result.Source.TagFilter).To(Equal("staging"))
			Expect(result.Source.RevSetFilter).To(Equal("public()"))
			Expect(result.Version.Ref).To(Equal("abc"))
		})
	})

})
