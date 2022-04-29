package hg

import (
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Hg", func() {
	repo := Repository{
		Path:   "/path/to/repo",
		Branch: "a_branch",
		IncludePaths: []string{
			"/path/1",
			"/path/2",
			"/path/3",
		},
		ExcludePaths: []string{
			"/path/4",
			"/path/5",
			"/path/6",
		},
	}
	emptyRepo := Repository{}
	Context("When making revset query fragments", func() {
		It("joins all given paths", func() {
			Expect(unionOfPaths(repo.IncludePaths)).To(Equal("file('re:/path/1')|file('re:/path/2')|file('re:/path/3')"))
		})

		It("produces the correct include fragment", func() {
			Expect(repo.makeIncludeQueryFragment()).To(Equal("file('re:/path/1')|file('re:/path/2')|file('re:/path/3')"))
			Expect(emptyRepo.makeIncludeQueryFragment()).To(Equal("all()"))
		})

		It("produces the correct exclude fragment", func() {
			Expect(repo.makeExcludeQueryFragment()).To(Equal("file('re:/path/4')|file('re:/path/5')|file('re:/path/6')"))
			Expect(emptyRepo.makeExcludeQueryFragment()).To(Equal("not all()"))
		})

	})

	Context("When getting metadata on a commit", func() {
		logResponse := `[
			{
				"rev": 16,
				"node": "f47d10f40bf7a96c2d853c6c6025ba35b6a9c499",
				"branch": "default",
				"phase": "draft",
				"user": "Jane Doe <jdoe@example.com>",
				"date": [1457968493, -32400],
				"desc": "foo",
				"bookmarks": [],
				"tags": ["tip"],
				"parents": ["4484191cd2e41c174ecc2604af06aeb2a21c247f"]
			}
		]`
		var metadata []CommitProperty
		var err error

		BeforeEach(func() {
			metadata, err = parseMetadata([]byte(logResponse))
		})

		It("extracts all expected fields", func() {
			Expect(err).To(BeNil())
			Expect(metadata).To(HaveLen(5))
		})

		It("extracts commit id, author and message", func() {
			Expect(err).To(BeNil())
			Expect(metadata[0].Name).To(Equal("commit"))
			Expect(metadata[0].Value).To(Equal("f47d10f40bf7a96c2d853c6c6025ba35b6a9c499"))

			Expect(metadata[1].Name).To(Equal("author"))
			Expect(metadata[1].Value).To(Equal("Jane Doe <jdoe@example.com>"))

			Expect(metadata[3].Name).To(Equal("message"))
			Expect(metadata[3].Value).To(Equal("foo"))
			Expect(metadata[3].Type).To(Equal("message"))
		})

		It("parses the date correctly", func() {
			// [1457968493, -32400] -> 2016-03-15 00:14:53 +0900
			// note the sign on the offset
			parsedTime, err := parseHgTime([]int64{1457968493, -32400})

			Expect(err).To(BeNil())

			year, month, day := parsedTime.Date()
			Expect(year).To(Equal(2016))
			Expect(month).To(Equal(time.Month(3)))
			Expect(day).To(Equal(15))

			hour, min, second := parsedTime.Clock()
			Expect(hour).To(Equal(0))
			Expect(min).To(Equal(14))
			Expect(second).To(Equal(53))

			_, offset := parsedTime.Zone()
			Expect(offset).To(Equal(32400))
		})

		It("parses the date and formats it in the expected ISO 8601 format", func() {
			Expect(err).To(BeNil())
			Expect(metadata[2].Name).To(Equal("author_date"))
			Expect(metadata[2].Value).To(Equal("2016-03-15 00:14:53 +0900"))
			Expect(metadata[2].Type).To(Equal("time"))
		})

		It("lists all tags of the commit", func() {
			Expect(err).To(BeNil())
			Expect(metadata[4].Name).To(Equal("tags"))
			Expect(metadata[4].Value).To(Equal("tip"))
		})
	})
})
