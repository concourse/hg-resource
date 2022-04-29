package main

import (
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"

	"testing"
)

func TestHgresource(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "Hgresource Suite")
}
