FROM mcr.microsoft.com/oss/cilium/cilium:v1.12.0 as cilium

FROM mcr.microsoft.com/oss/go/microsoft/golang:1.18 AS azure-ipam
ARG VERSION
WORKDIR /azure-ipam
COPY ./azure-ipam .
RUN CGO_ENABLED=0 go build -a -o bin/azure-ipam -trimpath -ldflags "-X main.version="$VERSION"" -gcflags="-dwarflocationlists=true" .

FROM mcr.microsoft.com/oss/go/microsoft/golang:1.18 AS azure-vnet
ARG VERSION
WORKDIR /azure-container-networking
COPY . .
RUN CGO_ENABLED=0 go build -a -o bin/azure-vnet -trimpath -ldflags "-X main.version="$VERSION"" -gcflags="-dwarflocationlists=true" cni/network/plugin/main.go

FROM mcr.microsoft.com/cbl-mariner/base/core:2.0 AS compressor
WORKDIR /dropgz
COPY dropgz .
COPY --from=azure-ipam /azure-ipam/*.conflist pkg/embed/fs
COPY --from=azure-ipam /azure-ipam/bin/* pkg/embed/fs
COPY --from=azure-vnet /azure-container-networking/cni/*.conflist pkg/embed/fs
COPY --from=azure-vnet /azure-container-networking/bin/* pkg/embed/fs
COPY --from=cilium /opt/cni/bin/cilium-cni pkg/embed/fs
RUN cd pkg/embed/fs/ && sha256sum * > sum.txt
RUN gzip --verbose --best --recursive pkg/embed/fs && for f in pkg/embed/fs/*.gz; do mv -- "$f" "${f%%.gz}"; done

FROM mcr.microsoft.com/oss/go/microsoft/golang:1.18 AS dropgz
ARG VERSION
WORKDIR /dropgz
COPY --from=compressor /dropgz .
RUN CGO_ENABLED=0 go build -a -o bin/dropgz -trimpath -ldflags "-X github.com/Azure/azure-container-networking/dropgz/internal/buildinfo.Version="$VERSION"" -gcflags="-dwarflocationlists=true" main.go

FROM scratch
COPY --from=dropgz /dropgz/bin/dropgz /dropgz
ENTRYPOINT [ "/dropgz" ]
