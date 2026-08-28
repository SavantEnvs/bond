# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile for Microsoft Bond's binary-deserializer fuzz harnesses,
# built ON TOP of the org C/C++ base. The base provides clang/llvm + libFuzzer +
# the build-contract ENV (CC/CXX/SANITIZER_FLAGS/LIB_FUZZING_ENGINE/STANDALONE_FUZZ_MAIN/SRC).
#
# Bond's C++ runtime needs Boost headers (mpl/preprocessor/...) and boost_thread/system
# (bond uses boost::call_once on clang). Baked as a root apt layer so mayhem/build.sh runs
# fully offline. The core generated IDL headers are PRE-generated with gbc and committed under
# mayhem/generated/, so NO Haskell toolchain is needed in this image.
FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG MAYHEM_JOBS=

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libboost-dev libboost-thread-dev libboost-system-dev \
 && rm -rf /var/lib/apt/lists/*

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
