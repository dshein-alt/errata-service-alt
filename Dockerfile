FROM registry.altlinux.org/alt/alt

RUN apt-get update && apt-get install -y golang git && rm -f /var/cache/apt/archives/*.rpm /var/cache/apt/*.bin /var/lib/apt/lists/*.*

WORKDIR /service
COPY . .
RUN touch ./config.yml
RUN go build -mod vendor -o service -ldflags "-X main.version=$(git tag --sort=-version:refname | head -n 1)" ./cmd/main.go

ENTRYPOINT ["./service", "-c", "./config.yml"]
