#!/usr/bin/env bash
cd "$(dirname "$0")"
source ./script/setup.sh
swift format format --in-place --recursive Sources Package.swift
