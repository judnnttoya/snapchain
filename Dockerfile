FROM rust:1.85 AS builder

LABEL maintainer="you@example.com"

WORKDIR /usr/src/app

ARG MALACHITE_GIT_REPO_URL=https://github.com/informalsystems/malachite.git
ENV MALACHITE_GIT_REPO_URL=$MALACHITE_GIT_REPO_URL
ARG MALACHITE_GIT_REF=13bca14cd209d985c3adf101a02924acde8723a5
ARG ETH_SIGNATURE_VERIFIER_GIT_REPO_URL=https://github.com/CassOnMars/eth-signature-verifier.git
ENV ETH_SIGNATURE_VERIFIER_GIT_REPO_URL=$ETH_SIGNATURE_VERIFIER_GIT_REPO_URL
ARG ETH_SIGNATURE_VERIFIER_GIT_REF=8deb4a091982c345949dc66bf8684489d9f11889

ENV RUST_BACKTRACE=full

# Copy early to improve caching of dependencies
COPY Cargo.toml build.rs ./
COPY src ./src

RUN echo "clear cache" # Invalidate cache to pick up latest eth-signature-verifier
RUN <<EOF
set -eu
apt-get update && apt-get install -y --no-install-recommends \
  libclang-dev git libjemalloc-dev llvm-dev make \
  protobuf-compiler libssl-dev openssh-client cmake ca-certificates

cd ..
git clone $ETH_SIGNATURE_VERIFIER_GIT_REPO_URL
cd eth-signature-verifier
git checkout $ETH_SIGNATURE_VERIFIER_GIT_REF
cd ..

git clone $MALACHITE_GIT_REPO_URL
cd malachite
git checkout $MALACHITE_GIT_REF
cd code
cargo build
EOF

RUN cargo build --release --bins

# FIXME: consider refactoring this step for more reproducibility
RUN target/release/setup_local_testnet

#################################################################################

FROM ubuntu:24.04

ARG GRPCURL_VERSION=1.9.1
ARG TARGETOS
ARG TARGETARCH

RUN <<EOF
  set -eu
  apt-get update && apt-get install -y --no-install-recommends curl
  curl -L https://github.com/fullstorydev/grpcurl/releases/download/v${GRPCURL_VERSION}/grpcurl_${GRPCURL_VERSION}_${TARGETOS}_${TARGETARCH}.deb > grpcurl.deb
  dpkg -i grpcurl.deb
  rm grpcurl.deb
  apt-get purge -y curl
  apt-get clean -y
  rm -rf /var/lib/apt/lists/*
EOF

WORKDIR /app

COPY --from=builder /usr/src/app/src/proto /app/proto
COPY --from=builder /usr/src/app/nodes /app/nodes
COPY --from=builder \
  /usr/src/app/target/release/snapchain \
  /usr/src/app/target/release/follow_blocks \
  /usr/src/app/target/release/setup_local_testnet \
  /usr/src/app/target/release/submit_message \
  /usr/src/app/target/release/perftest \
  /app/

ENV RUSTFLAGS="-Awarnings"

CMD ["./snapchain", "--id", "1"]
