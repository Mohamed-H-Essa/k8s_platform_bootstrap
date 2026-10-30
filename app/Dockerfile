# Two stages: build a static binary, then ship it alone on distroless (no shell, no
# package manager, runs as a non-root user). The final image is the binary plus
# distroless (CA certificates, tzdata): almost nothing for a scanner, or an attacker, to find.
FROM golang:1.27-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/shortener ./cmd/shortener

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/shortener /shortener
USER 65532:65532
EXPOSE 8080 9090
ENTRYPOINT ["/shortener"]
