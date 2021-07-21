ARG base_image=alpine:latest
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
RUN apk update && apk upgrade
RUN apk add --update \
    bash \
    curl \
    gnupg \
    gzip \
    jq \
    openssh \
    tar \
    python3 \
    python3-dev \
    py3-pip \
    build-base

RUN pip3 install mercurial
RUN pip3 install hg-evolve

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
