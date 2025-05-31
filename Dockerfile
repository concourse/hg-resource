ARG base_image=cgr.dev/chainguard/wolfi-base
ARG builder_image=concourse/golang-builder

ARG BUILDPLATFORM
FROM --platform=${BUILDPLATFORM} ${builder_image} AS builder

ARG TARGETOS
ARG TARGETARCH
ENV GOOS=$TARGETOS
ENV GOARCH=$TARGETARCH

COPY . /src
WORKDIR /src
RUN go mod download
ENV CGO_ENABLED=0
RUN go build -o /assets/hgresource ./hgresource
RUN set -e; for pkg in $(go list ./...); do \
    go test -o "/tests/$(basename $pkg).test" -c $pkg; \
    done

FROM ${base_image} AS resource
RUN apk --no-cache add \
    cmd:hg \
    ca-certificates \
    gnupg \
    openssh-client \
    python3-dev \
    cmd:pip3

RUN pip3 install hg-evolve
COPY --from=builder /assets /opt/resource
RUN chmod +x /opt/resource/*
RUN ln -s /opt/resource/hgresource /opt/resource/in; ln -s /opt/resource/hgresource /opt/resource/out; ln -s /opt/resource/hgresource /opt/resource/check
COPY hgrc /etc/mercurial/hgrc

FROM resource AS tests
RUN apk --no-cache add bash jq cmd:ssh-keygen
COPY --from=builder /tests /go-tests
RUN set -e; for test in /go-tests/*.test; do \
    $test; \
    done

COPY /test /test
RUN /test/all.sh

FROM resource
