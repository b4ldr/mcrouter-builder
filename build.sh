#!/bin/sh
docker run -it -v "${PWD}":/build debian:buster /build/docker_entry.sh
