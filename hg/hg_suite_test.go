package hg_test

import (
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	"testing"
)

func TestHg(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Hg Suite")
}
