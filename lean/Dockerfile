# Lean toolchain and Mathlib for the Pact mechanization (pact-formalization).
# Build from the repository root:
#   podman build -t pact-lean -f lean/Dockerfile .
# Run (writes to ./results/lean on the host):
#   podman run --rm -v "$PWD/results/lean:/results:z" pact-lean full

FROM docker.io/library/ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/*

ENV ELAN_HOME=/opt/elan
ENV PATH=/opt/elan/bin:$PATH
RUN curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
      | sh -s -- -y --no-modify-path --default-toolchain none

COPY pact-formalization /artifact/pact-formalization
WORKDIR /artifact/pact-formalization

# The toolchain pinned in lean-toolchain, the dependencies pinned in lake-manifest.json,
# and Mathlib's prebuilt files. The Pact proofs themselves are built when the container runs.
RUN elan toolchain install "$(cat lean-toolchain)" \
    && lake exe cache get

COPY lean/check.sh /artifact/check.sh
ENTRYPOINT ["/artifact/check.sh"]
CMD ["full"]
