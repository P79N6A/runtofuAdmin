# 这里假定 git 上项目名就是服务名，如果出现了例外，记得修改 git 项目名，而不要在这里修改。
# 仅当项目初始化还未上传 git 时可以临时的手动设置 PACKAGE_NAME 值，绕过各种检查。
SUB_PACKAGE  := $(subst $(shell git rev-parse --show-toplevel),,$(CURDIR))
PACKAGE_ROOT := $(shell git remote -v | grep '^origin\s.*(fetch)$$' | awk '{print $$2}' | sed -E 's/^.*(\/\/|@)(.*)\.git\/?$$/\2/' | sed 's/:/\//g')
PACKAGE_NAME = $(PACKAGE_ROOT)$(SUB_PACKAGE)

APP_ROOT := $(shell dirname $(PACKAGE_NAME))
APP      := $(shell basename $(PACKAGE_NAME))
GROUP    := $(shell dirname $(APP_ROOT))

OUTPUT     = $(CURDIR)/output
CONF       = $(CURDIR)/conf
GLIDE_LOCK = $(CURDIR)/glide.lock
GLIDE_YAML = $(CURDIR)/glide.yaml

OUTPUT_LIB_DIR = $(OUTPUT)/lib

OUTPUT_DIRS = conf data bin deploy-meta

BUILD_ROOT   := $(shell git rev-parse --show-toplevel)/build
BUILD_TARGET = src/$(PACKAGE_ROOT)
BUILD_DIR    = $(BUILD_ROOT)/$(BUILD_TARGET)
include ./Makefile.in

export GOPATH=$(BUILD_ROOT)
export GOBIN=$(BUILD_ROOT)/bin
export GO15VENDOREXPERIMENT=1

.DEFAULT: all
all: build

build: clean prepare fmt
	cd "$(BUILD_DIR)" && go build -o "$(OUTPUT)/bin/$(APP)" "$(BUILD_DIR)$(SUB_PACKAGE)/main.go" 

test_client:
	cd "$(BUILD_DIR)" && go build -o "$(OUTPUT)/bin/$(APP)_test" "$(BUILD_DIR)$(SUB_PACKAGE)/test.go"

fmt:
	go fmt $$(glide novendor)

clean:
	for i in $(OUTPUT_DIRS) control.sh; do rm -rf "$(OUTPUT)/$$i"; done
	git checkout -- $(RANK_SEARCH_GO_FILE) $(RANK_REC_GO_FILE) 

prepare:
	mkdir -p "$(OUTPUT)/log"
	for i in $(OUTPUT_DIRS); do mkdir -p "$(OUTPUT)/$$i"; done
	cp -r data/* $(OUTPUT)/data/

	cp -vr "$(CONF)" "$(OUTPUT)"
	cp -v "$(CURDIR)/control.sh" "$(OUTPUT)"
	cp -vr "$(CURDIR)/deploy-meta" "$(OUTPUT)"
	sed -i'' -e 's/%(APP)/$(APP)/' "$(OUTPUT)/control.sh" "$(OUTPUT)/deploy-meta/supervisor.conf.append"
run:
	cd "$(OUTPUT)" && bin/$(APP)

test:
	git rev-parse --show-toplevel
	echo "$(BUILD_DIR)" "$(SUB_PACKAGE)"
	cd "$(BUILD_DIR)$(SUB_PACKAGE)" && go test  git.xiaojukeji.com/trade-engine/search-broker/service -bench=".*" -cpuprofile $(BUILD_DIR)/cpu.prof
	#cd "$(BUILD_DIR)$(SUB_PACKAGE)" && go test git.xiaojukeji.com/trade-engine/search-broker/client
	#cd "$(BUILD_DIR)$(SUB_PACKAGE)" && go test $$(glide novendor)
	cd "$(BUILD_DIR)$(SUB_PACKAGE)" && go test git.xiaojukeji.com/trade-engine/search-broker/model/fc-proxy

init:
	sed -i'' -e 's/^package:.*/package: $(subst /,\/,$(PACKAGE_NAME))/' "$(GLIDE_YAML)"
	
	mkdir -p "$(shell dirname $(BUILD_DIR))"
	if [ ! -e "$(BUILD_DIR)" ]; then ln -s "$(shell echo $(BUILD_TARGET) | sed -E 's/[a-zA-Z0-9_.-]+/../g')" "$(BUILD_DIR)"; fi

glide-up: glide-update
glide-update:
	glide update

glide-i: glide-install
glide-install:
	glide install

.PHONY: all build fmt clean prepare run test init glide-up glide-update glide-i glide-install
$(VERBOSE).SILENT:
