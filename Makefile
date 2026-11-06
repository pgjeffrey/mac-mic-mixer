ARCH ?= arm64
CXX ?= c++

.PHONY: help sources test build package source-archive check
help:
	@echo 'make sources         获取并核对固定版本的第三方源码'
	@echo 'make test            运行便携音频测试与项目检查（Linux/macOS）'
	@echo 'make build           在 Mac 上构建应用与虚拟驱动，默认 Apple 芯片'
	@echo 'make package         在 Mac 上生成安装包、卸载包和对应源码归档'
	@echo 'make source-archive  生成包含第三方源码的源代码归档'
	@echo 'ARCH=x86_64          可选 Intel 构建；仍须单独验证'

sources:
	python3 tools/fetch_sources.py

check:
	python3 tools/check_project.py

test: check
	python3 -m unittest discover -s tests -p 'test_*.py' -v
	mkdir -p .build/tests
	$(CXX) -std=c++17 -Wall -Wextra -Werror -g -O1 -pthread -fsanitize=address,undefined -fno-omit-frame-pointer -I native/core tests/audio_pipe_test.cpp -o .build/tests/audio_pipe_test
	.build/tests/audio_pipe_test

build: sources
	python3 tools/build_macos.py --arch $(ARCH)

package: build
	python3 tools/package_macos.py --arch $(ARCH)

source-archive: sources
	python3 tools/source_archive.py
