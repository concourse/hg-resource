ARG base_image=ubuntu:latest
ARG builder_image=concourse/golang-builder

FROM ${builder_image} as builder
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

FROM ${base_image} AS resource
USER root
RUN apt update && apt upgrade -y -o Dpkg::Options::="--force-confdef"
RUN apt update && apt install -y --no-install-recommends \
      curl \
      ca-certificates \
      gnupg \
      jq \
      openssh-client \
      python3 \
      python3-pip \
      build-essential \
      python3-all-dev \
      python3-setuptools \
      python3-wheel \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install mercurial \
    && pip3 install hg-evolve

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
