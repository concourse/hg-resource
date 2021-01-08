FROM concourse/golang-builder as builder
WORKDIR /src

COPY go.mod .
COPY go.sum .
RUN go mod download

COPY . .
ENV CGO_ENABLED 0
RUN go build -o /assets/hgresource ./hgresource
RUN set -e; for pkg in $(go list ./...); do \
		go test -o "/tests/$(basename $pkg).test" -c $pkg; \
	done

FROM ubuntu:bionic AS resource
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      ca-certificates \
      gnupg \
      jq \
      openssh-client \
      python \
      python-pip \
      build-essential \
      python-all-dev \
      python-setuptools \
      python-wheel \
    && rm -rf /var/lib/apt/lists/* \
    && pip2 install mercurial \
    && pip2 install hg-evolve

COPY --from=builder /assets /opt/resource
RUN chmod +x /opt/resource/*
RUN ln -s /opt/resource/hgresource /opt/resource/in; ln -s /opt/resource/hgresource /opt/resource/out; ln -s /opt/resource/hgresource /opt/resource/check
ADD hgrc /etc/mercurial/hgrc

FROM resource AS tests
COPY --from=builder /tests /go-tests
RUN set -e; for test in /go-tests/*.test; do \
		$test; \
	done

COPY /test /test
RUN /test/all.sh

FROM resource
