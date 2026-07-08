#!/bin/sh
# 同期マージ・ロックアウト・自動ロック・バックアップ・後方互換のユニットテスト。
# Xcode不要 — swiftc があればどこでも動く (macOS / Linux)。
# CryptoKit/CommonCryptoに依存するファイル(BackupCodec, CryptoService)は
# Apple OS専用のため、Foundationのみで完結するロジックをテスト対象にしている。
set -e
cd "$(dirname "$0")"
swiftc -o /tmp/privacyvault-tests \
  ../Sources/Models/VaultItem.swift \
  ../Sources/Storage/VaultMerge.swift \
  ../Sources/Storage/BackupFormat.swift \
  ../Sources/Security/LockoutPolicy.swift \
  ../Sources/App/AutoLock.swift \
  main.swift
/tmp/privacyvault-tests
