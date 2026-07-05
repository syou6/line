#!/bin/sh
# 同期マージ・モデルの後方互換のユニットテストを実行する。
# Xcode不要 — swiftc があればどこでも動く (macOS / Linux)。
set -e
cd "$(dirname "$0")"
swiftc -o /tmp/privacyvault-merge-tests \
  ../Sources/Models/VaultItem.swift \
  ../Sources/Storage/VaultMerge.swift \
  main.swift
/tmp/privacyvault-merge-tests
