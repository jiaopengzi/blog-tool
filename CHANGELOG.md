# Changelog

本文件将记录本项目的所有重要变更。

该格式基于 [Keep a Changelog](https://keepachangelog.com),
本项目遵循 [语义化版本控制](https://semver.org/spec/v2.0.0.html)。

## [v0.2.2] - 2026-02-28

### 🐞 Fix

- 修复 docker daemon.json 写入问题

## [v0.2.1] - 2026-02-28

### ⚙️ Ci

- 自动化部署，不使用 `git savetag`

## [v0.2.0] - 2026-02-28

### ⚙️ Ci

- 开发发布策略

### ✨ Feat

- 兼容 Ubuntu
- **server:** 增加证书私钥签名可执行文件步骤

### 🐞 Fix

- registry mirrors list
- 手动证书私钥签名
- 修复产物不存在的情况，直接覆盖

### 📝 Docs

- 兼容 Ubuntu
- 更新 readme

## [v0.1.2] - 2026-02-09

### ⚙️ Ci

- 不使用跳过，直接报错

## [v0.1.1] - 2026-02-09

### ⚙️ Ci

- build 后执行同步

### 📝 Docs

- 配置文档

## [v0.1.0] - 2026-02-09

### ⚙️ Ci

- 调试 action build
- 单线执行 action
- 调试 build 脚本
- 调试脚本
- 自动化同步和分发

### ✨ Feat

- 工具首次提交
