# 手元でビルドするとき用。
#
#   git clone --branch 2025q3 --recurse-submodules \
#       https://github.com/Keychron/qmk_firmware.git ../qmk_firmware
#   make
#
# 出力: ../qmk_firmware/keychron_c100_8k_midi.bin
#
# QMK 側のツリーを汚さずにビルドするため、一時ディレクトリに
# このリポジトリへのシンボリックリンクを張って QMK_USERSPACE として渡している。

QMK_HOME ?= ../qmk_firmware
USERSPACE_PATH ?= $(CURDIR)

.PHONY: build clean

build:
	@set -eu; \
	temp_dir=$$(mktemp -d); \
	ln -s "$(USERSPACE_PATH)" "$$temp_dir/userspace"; \
	trap 'rm -f "$$temp_dir/userspace"; rmdir "$$temp_dir"' EXIT; \
	$(MAKE) -C "$(QMK_HOME)" keychron/c100_8k:midi QMK_USERSPACE="$$temp_dir/userspace"

clean:
	@set -eu; \
	temp_dir=$$(mktemp -d); \
	ln -s "$(USERSPACE_PATH)" "$$temp_dir/userspace"; \
	trap 'rm -f "$$temp_dir/userspace"; rmdir "$$temp_dir"' EXIT; \
	$(MAKE) -C "$(QMK_HOME)" clean QMK_USERSPACE="$$temp_dir/userspace"
